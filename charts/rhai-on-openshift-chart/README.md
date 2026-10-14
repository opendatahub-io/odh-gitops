# RHAI on OpenShift Helm Chart

A Helm chart for installing ODH/RHOAI dependencies and component configurations on OpenShift.

## Overview

This chart provides a flexible way to install the operators and configurations required by OpenShift AI (RHOAI) and Open Data Hub (ODH). It supports:

- **Deploy profiles**: Preconfigured deployment types (e.g., `rhaii`) that enable the right components and dependencies with a single flag
- **Component-based installation**: Enable high-level components (kserve, kueue, aipipelines, ...) and their dependencies are automatically installed
- **DSC v3 rendering**: The chart renders `datasciencecluster.opendatahub.io/v3` (requires ODH/RHOAI operator 3.6+); DSC v2 values keys are translated automatically, and ambiguous or removed input fails the render with an actionable message (see [Upgrading from DSC v2 values](#upgrading-from-dsc-v2-values))
- **Tri-state dependency management**: Dependencies can be `auto` (install if needed), `true` (always install), or `false` (skip - user has it already)
- **OLM installation**: Operators are installed via Operator Lifecycle Manager (OLM)
- **Idempotent installation**: Run the same command multiple times until all resources are applied

## Quick Start

> [!NOTE]
> All commands below assume you are in the repository root directory.

All components, including monitoring, default to `Removed`. You can use a **profile** or a **values file** to enable the components you need.

### Using a profile

Profiles preconfigure which components and dependencies to install with a single flag:

```bash
# Set OPERATOR_TYPE to: odh | rhoai
export OPERATOR_TYPE=${OPERATOR_TYPE:-odh}

# Install RHAII stack (KServe + required dependencies for inference)
helm upgrade --install ${OPERATOR_TYPE} ./charts/rhai-on-openshift-chart -n ${OPERATOR_TYPE}-gitops --create-namespace \
  --set profile=rhaii \
  --set operator.type=${OPERATOR_TYPE}
```

See [Deploy Profiles](#deploy-profiles) for available profiles and details.

### Using a values file

For full control or to enable all components, use a values file:

| Values File | Description |
|-------------|-------------|
| [`docs/examples/values-all-components-managed.yaml`](../../docs/examples/values-all-components-managed.yaml) | Enable all components and monitoring (full platform) |
| [`docs/examples/values-inference-only.yaml`](../../docs/examples/values-inference-only.yaml) | Enable only KServe for inference/model serving |

```bash
export OPERATOR_TYPE=${OPERATOR_TYPE:-odh}

# Install with all components enabled
helm upgrade --install ${OPERATOR_TYPE} ./charts/rhai-on-openshift-chart -n ${OPERATOR_TYPE}-gitops --create-namespace \
  -f docs/examples/values-all-components-managed.yaml \
  --set operator.type=${OPERATOR_TYPE}

# Wait for CRDs to be created, then run again to create CRs
helm upgrade --install ${OPERATOR_TYPE} ./charts/rhai-on-openshift-chart -n ${OPERATOR_TYPE}-gitops \
  -f docs/examples/values-all-components-managed.yaml \
  --set operator.type=${OPERATOR_TYPE}
```

## Installation Flow

Due to CRD dependencies (operators create CRDs that are needed for CR resources), installation requires multiple runs:

```bash
for i in {1..5}; do
  helm upgrade --install ${OPERATOR_TYPE} ./charts/rhai-on-openshift-chart -n ${OPERATOR_TYPE}-gitops --create-namespace --set operator.type=${OPERATOR_TYPE}
  sleep 60
done
```

**What happens:**
1. **First run**: Operators are installed via OLM (Namespace, OperatorGroup, Subscription). CRs are skipped because CRDs don't exist yet.
2. **Subsequent runs**: Once operators are ready and CRDs exist, CR configurations are created.
3. **Later runs**: Idempotent - no changes if everything is already deployed.

### Enable Authorino TLS

The Kuadrant operator creates the Authorino resource automatically. To enable TLS, use the provided script which:

1. Annotates the Authorino service to trigger TLS certificate generation
2. Waits for the TLS secret to be created
3. Patches the Authorino CR to enable TLS

```bash
# Run the script to enable TLS
KUSTOMIZE_MODE=false ./scripts/prepare-authorino-tls.sh
```

The script can be customized with environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `KUADRANT_NS` | `kuadrant-system` | Namespace where Kuadrant is installed |
| `K8S_CLI` | `kubectl` | Kubernetes CLI to use (kubectl or oc) |
| `KUSTOMIZE_MODE` | `true` | If false, patches the Authorino CR directly instead of updating the kustomization.yaml |

> **Note**: The `dependencies.rhcl.config.tlsEnabled` Helm value is intended for ArgoCD use cases. For CLI use case, use the script above.

### KServe Gateway

When KServe is Managed, the chart creates a Gateway CR for inference traffic (`components.kserve.gateway.create` defaults to `auto`).

You **must** configure which namespaces can attach HTTPRoutes to the gateway via `allowedRoutes.namespaces.from` in the listener spec. The chart will fail if this is not set. Use `Selector` (recommended) to restrict by namespace labels, or `Same` to allow only the gateway's own namespace.

When using `Selector`, the specified labels must be applied to each target namespace.

```yaml
components:
  kserve:
    dsc:
      managementState: Managed
    gateway:
      spec:
        gatewayClassName: openshift-ai-inference
        listeners:
          - name: https
            port: 443
            protocol: HTTPS
            allowedRoutes:
              namespaces:
                from: Selector
                selector:
                  matchLabels:
                    inference-gateway-access: "true"
```

### Enable Models as Service

To enable Models as Service, set `components.aigateway.dsc.managementState` and
`components.aigateway.dsc.modelsAsAService.managementState` to `Managed`.

Gateway and GatewayClass are created automatically when MaaS is Managed
(`components.aigateway.modelsAsAService.gateway.create` / `gatewayClass.create`
default to `auto`, matching the KServe gateway pattern). Set either flag to
`false` to skip chart-managed creation and supply your own resources, or to
`true` to always create them.

When using the chart-managed Gateway, you **must** configure
`allowedRoutes.namespaces.from` in the listener spec — the chart will fail if
this is not set. Use `Selector` (recommended) to restrict by namespace labels,
or `Same` to allow only the gateway's own namespace. When using `Selector`, the
specified labels must be applied to each target namespace.

Customize the listener for your environment (hostname and TLS / certificate
secret as needed). The default annotations
(`security.opendatahub.io/authorino-tls-bootstrap` and
`opendatahub.io/managed`) should be kept unless you intentionally change MaaS
TLS / ownership behavior.

For example:

```yaml
# values.yaml
components:
  aigateway:
    dsc:
      managementState: Managed
      modelsAsAService:
        managementState: Managed
    modelsAsAService:
      gateway:
        spec:
          gatewayClassName: maas-gateway-class
          listeners:
            - name: https
              port: 443
              # hostname: <HOSTNAME> # Uncomment this line to use a specific hostname.
              protocol: HTTPS
              allowedRoutes:
                namespaces:
                  # The following is an example of how to restrict the namespaces to the interested ones.
                  from: Selector
                  selector:
                    matchExpressions:
                    - key: kubernetes.io/metadata.name
                      operator: In
                      values:
                      - openshift-ingress
                      - <LLM_INFERENCE_SERVICE_NAMESPACE>
              tls:
                certificateRefs:
                - group: ''
                  kind: Secret
                  name: <SECRET_NAME>
                mode: Terminate
```

## Deploy Profiles

Profiles provide preconfigured deployment types that set the right `managementState` for components and dependencies with a single `--set profile=<name>` flag.

| Profile | Description | Components enabled | Dependencies auto-installed |
|---------|-------------|--------------------|-----------------------------|
| `default` | All components Removed (manual configuration) | None | None |
| `rhaii` | RHAII inference/model-serving stack | kserve | certManager, leaderWorkerSet, rhcl |
| `maas` | Models as a Service platform | aigateway (with `modelsAsAService`), kserve | certManager, rhcl |
| `ai-grid` | AI Grid multi-cluster routing | aigateway (aiGrid) | None |

With ordinary chart defaults, the `maas` profile installs `certManager` and `rhcl` (through `kserve`) but not
`leaderWorkerSet` — `aigateway`'s `null` dependency default for it is not activated. Enable it explicitly
with `--set components.aigateway.dependencies.leaderWorkerSet=true`. The profile also requires Gateway
listener configuration for both `aigateway` and `kserve` before it renders — see
[Enable Models as Service](#enable-models-as-service) and [KServe Gateway](#kserve-gateway).

Profiles are defined as YAML files in the [`profiles/`](profiles/) directory. See the [Contributing guide](../../CONTRIBUTING.md#adding-a-new-deploy-profile) for how to add new profiles.

### AI Grid

AI Grid is opt-in. The default profile leaves it disabled and omits `aiGrid` for compatibility
with payloads that do not yet expose the field. `--set profile=ai-grid` explicitly sets AIGateway
and its `aiGrid` sub-component to `Managed`; other sub-components remain `Removed`.
An explicit `components.aigateway.dsc.aiGrid.managementState=Removed` overrides the profile.

The AI Gateway operator owns the Grid operator and its CRDs (ai-gateway-operator PR #148).
This chart does not install a second Grid operator. The profile requires an operator payload
containing opendatahub-operator PR #4186; chart version `3.6.0` alone does not guarantee that payload.

The profile also enables the Helm-managed gateway and enrollment workloads. Both runtime
`enabled` flags default to `true`, but resources render only when the effective AIGateway
and `aiGrid` management states are both `Managed`. Thus the default profile installs neither.
Setting either state to `Removed` suppresses both runtimes on the next Helm upgrade or GitOps
sync with pruning enabled, even if their `enabled` flags remain `true`. Editing the live DSC
alone does not update a Helm release.
Set an individual runtime's `enabled: false` to supply that service externally.

Use [`values-ai-grid-hub.yaml`](../../docs/examples/values-ai-grid-hub.yaml) to configure a
hub's hostname, gateway ConfigMap and database Secret. The profile defaults render the upstream
gateway status endpoint and built-in enrollment database; configure routing before using it
for inference. Use a database provisioned for enrollment; do not point it at the MaaS database
without a separate database/schema arrangement. Removal does not delete externally supplied
ConfigMaps, Secrets or databases, or resources retained by upstream Helm hooks/retention policies.

The gateway/enrollment charts are version `0.2.0`, vendored from `praxis-proxy/grid@3359afdcddda926f3cdf986f5173f12b30b40aae`.
The parent defaults to the Grid gateway image, rather than the generic Praxis AI image.
Refresh with `make update-ai-grid-charts GRID_REF=<tag-or-sha>`; this reapplies the downstream
image/review patches and runtime template adapter, updates the dependency lock, and regenerates
docs and snapshots. The adapter exports named resource templates so the parent can gate rendering
using its resolved DSC state. Standalone subchart installs still render directly. This avoids
relying on Helm dependency conditions to evaluate profile templates.

Downstream builds can inject full image references through `global.relatedImages`, using the
same `name`/`value` convention as the XKS chart. These overrides take precedence over subchart
image repository/tag/digest settings and apply to both containers and bootstrap/invite Jobs.

| Name | Image |
|------|-------|
| `RELATED_IMAGE_ODH_PRAXIS_AI_GRID_GATEWAY_IMAGE` | Grid gateway |
| `RELATED_IMAGE_ODH_PRAXIS_AI_GRID_ENROLLMENT_IMAGE` | Enrollment service and Jobs |
| `RELATED_IMAGE_ODH_PRAXIS_AI_GRID_POSTGRES_IMAGE` | Optional built-in PostgreSQL and database initialization |
| `RELATED_IMAGE_ODH_PRAXIS_AI_GRID_OVERLAY_SYNC_IMAGE` | Optional gateway overlay-sync containers |
| `RELATED_IMAGE_ODH_PRAXIS_AI_GRID_TEST_IMAGE` | Gateway Helm connectivity test (requires `sh`, `wget`, and `nc`) |

```yaml
global:
  relatedImages:
    - name: RELATED_IMAGE_ODH_PRAXIS_AI_GRID_GATEWAY_IMAGE
      value: registry.example.com/rhai/grid-gateway@sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa
```

The parent pins gateway, enrollment, PostgreSQL and Helm test images by digest. When
changing an image repository/tag, also replace its digest (or use `global.relatedImages`).
Downstream payloads should provide digest-qualified related images, including enrollment,
whose image also runs the CA bootstrap Job. Subchart standalone image settings retain the
upstream defaults; the parent supplies the release pins.

Gateway, enrollment, bootstrap, invite and database containers have CPU/memory budgets.
These are starting limits; size them for your workload. PostgreSQL uses a read-only root
with writable home, temporary and socket directories plus its data PVC.

Ingress policies are enabled by default. Gateway clients in the release namespace must
have `grid.opendatahub.io/gateway-client: "true"`; the default also admits OpenShift router
namespaces labelled `network.openshift.io/policy-group: ingress`. Replace
`praxis-gateway.networkPolicy.from` with the actual inference clients for your topology.
Enrollment admits its invite Job, and router namespaces when its Route is enabled;
add direct clients under `grid-enrollment.networkPolicy.from`. Built-in PostgreSQL admits
only this release's enrollment pods. A NetworkPolicy-capable CNI is required; node probes
are not blocked. Direct LoadBalancer deployments must configure their permitted sources.

Invite Jobs require Kubernetes ValidatingAdmissionPolicy support (GA in Kubernetes 1.30).
Their admission policy limits writes to configured Opaque invite Secrets and rejects
ServiceAccount-token annotations, independently of optional ACM delivery policies.

For an inline or external gateway config, a Route requires `route.externalTls: true` to
attest that its listener actually serves TLS. Generated configs retain their TLS validation.
Explicit HTTP telemetry endpoints require `gatewayConfig.telemetry.allowInsecure: true`;
use this only for a trusted local collector, without credentials. Environment-supplied
exporter settings must follow the same transport policy. The Helm test checks TCP
connectivity only; validate application responses and TLS identities with site-specific tests.

The Grid operator image belongs to the platform payload. Override it through
`operator.<odh|rhoai>.olm.config.env` with `RELATED_IMAGE_ODH_PRAXIS_AI_GRID_OPERATOR_IMAGE`
when testing a custom payload, rather than setting a Helm-managed operator image.

### How profiles work

- When `profile` is set, it provides default `managementState` values for components that are not explicitly configured
- **Explicit values always win**: setting `--set components.kserve.dsc.managementState=Removed` overrides the profile
- Profile `default` preserves the standard behavior — all components are `Removed` unless you enable them manually
- Profiles also control component dependency defaults (e.g., `rhaii` disables `jobSet` for kserve since it's not needed for inference-only deployments)

### Example: RHAII deployment

```bash
helm upgrade --install rhoai ./charts/rhai-on-openshift-chart -n rhoai-gitops --create-namespace \
  --set profile=rhaii \
  --set operator.type=rhoai
```

This installs the RHOAI operator with KServe enabled and its required dependencies (cert-manager, leader-worker-set, RHCL/Kuadrant).

## Configuration

### Operator

Choose between ODH (Open Data Hub) or RHOAI (Red Hat OpenShift AI) operator:

```yaml
operator:
  enabled: true
  type: rhoai # odh | rhoai
```

| Type | Operator | Namespace | Source |
|------|----------|-----------|--------|
| `odh` | opendatahub-operator | opendatahub-operator-system | community-operators |
| `rhoai` | rhods-operator | redhat-ods-operator | redhat-operators |

### Components

High-level features that:

1. Configure the DataScienceCluster (DSC) `managementState`
2. Automatically enable their required dependencies when active (Managed or Unmanaged)

| managementState | Dependencies auto-enabled |
|-----------------|---------------------------|
| `Managed` | Yes |
| `Unmanaged` | Yes |
| `Removed` | No |

| Component          | Description                        | Default State | Dependencies |
|--------------------|------------------------------------|---------------|--------------|
| `aiHub`            | AI Hub (Model Registry)            | Removed | - |
| `aigateway`        | AI Gateway (Models as a Service)   | Removed | certManager, leaderWorkerSet, rhcl |
| `aipipelines`      | AI Pipelines                       | Removed | - |
| `dashboard`        | Dashboard (structural: `standard`, `maasPortal`) | Removed | - |
| `data`             | Data (structural: `featureStore`, `dataRegistry`) | Removed | - |
| `kserve`           | KServe model serving               | Removed | certManager, leaderWorkerSet, jobSet, rhcl, customMetricsAutoscaler |
| `kueue`            | Kueue job queuing                  | Removed | certManager, kueue |
| `mcplifecycleoperator` | MCP Lifecycle Operator         | Removed | - |
| `mlflowoperator`   | MLflow tracking and model registry | Removed | - |
| `ogx`              | OGX                                | Removed | nfd, nvidiaGPUOperator |
| `ray`              | Ray distributed computing          | Removed | certManager |
| `sparkoperator`    | Spark Operator                     | Removed | - |
| `trainer`          | Trainer                            | Removed | certManager, jobSet |
| `trustyai`         | TrustyAI                           | Removed | - |
| `workbenches`      | Workbenches (incl. `workbenchesV2`) | Removed | - |

With ordinary chart defaults, `aigateway`'s `null`-defaulted dependencies are not activated when the
component is enabled — set them to `true` explicitly to install them.

#### Structural components

`dashboard` and `data` are **structural** in DSC v3: they have no component-level
`managementState`. Each child carries its own state, and the component-level
dependencies activate when any child is Managed or Unmanaged:

```yaml
components:
  dashboard:
    dsc:
      standard:
        managementState: Managed    # core Dashboard
      maasPortal:
        managementState: Removed    # MaaS Consumer Portal
  data:
    dsc:
      featureStore:
        managementState: Managed    # Feature Store (replaces feastoperator)
      dataRegistry:
        managementState: Removed    # Data Registry
```

#### Upgrading from DSC v2 values

The chart renders `datasciencecluster.opendatahub.io/v3` and requires an operator
version that serves v3 (ODH/RHOAI 3.6+). Values files written for DSC v2 keep
working: deprecated keys are translated automatically, and ambiguous or removed
input fails the render with an actionable message.

| Deprecated DSC v2 key | DSC v3 equivalent | Behavior |
|-----------------------|-------------------|----------|
| `components.modelregistry` | `components.aiHub` | Translated (`dsc.registriesNamespace` → `dsc.instancesNamespace`; dependencies and operator-type defaults carried over) |
| `components.feastoperator` | `components.data.dsc.featureStore` | Translated |
| `components.dashboard.dsc.managementState` | `components.dashboard.dsc.standard.managementState` | Translated |
| `components.trainingoperator` | — | **Fails**: component removed in DSC v3; use `components.trainer` |
| `components.kserve.dsc.wva` | — | **Fails**: removed in DSC v3; the operator treats WVA as always Removed |

Rules:
- Conflicts can extend beyond the mapped replacement — migrate your values,
  then remove the deprecated key. Management-state and namespace values count
  as set when non-null and non-empty; dependencies and defaults maps count
  when non-empty, even if an entry is `false` or `null`:
  - `components.modelregistry` conflicts with any of
    `components.aiHub.dsc.managementState`,
    `components.aiHub.dsc.instancesNamespace`, or
    `components.aiHub.dependencies`.
  - `components.feastoperator` conflicts with any of
    `components.data.dsc.featureStore.managementState`,
    `components.data.dsc.dataRegistry.managementState`,
    `components.data.dependencies`, or `components.data.defaults`.
  - The legacy `components.dashboard.dsc.managementState` conflicts only with
    `components.dashboard.dsc.standard.managementState` or
    `components.dashboard.dsc.maasPortal.managementState`, not dashboard
    dependencies or defaults.
  - `components.modelregistry.defaults.<operator-type>.registriesNamespace`
    conflicts with
    `components.aiHub.defaults.<operator-type>.instancesNamespace` when both
    namespaces are non-empty for the same operator type and the aiHub value
    differs from the chart default. If aiHub has the chart default, a
    non-empty old namespace is carried over; without one, the aiHub value
    remains unchanged.
- Conflict and removed-key failures are validated when the chart renders
  the DSC, which requires the v3 CRD — on a first install before the
  operator serves it, invalid values surface on the next upgrade.
- `null` never counts as set: a legacy block whose values are all `null`
  or empty is pruned silently (no deprecation notice), `null` leaves in a
  set block carry nothing, and a whole key set to `null` is rejected by
  the values schema — remove the key instead.
- Translated stanzas render with a deprecation comment, and `helm install` prints
  a **Deprecation Notices** section — remove the old keys at your convenience.
- Deprecated keys are removed in the next chart major; translate manually before
  then (the table above is the complete mapping).
- `components.aiHub.dsc.instancesNamespace` is immutable in the operator while
  `aiHub` is `Managed`; the translation preserves your existing value across the
  upgrade (including operator-type defaults).

#### Example: upgrading a chart 3.4.x release

For a release installed with chart 3.4.x (DSC v2) — e.g. with
`components.modelregistry.dsc.registriesNamespace: odh-model-registry` — against
a 3.6 operator:

```bash
# Set OPERATOR_TYPE to the operator type of the release you are upgrading
# (odh | rhoai); it must match the existing install. The guard below fails
# loudly when the variable is unset and keeps an already-set value, and the
# validation in step 2 rejects any value other than odh or rhoai:
: "${OPERATOR_TYPE:?set OPERATOR_TYPE to odh or rhoai, matching the existing install}"

# 1. Upgrade the operator subscription to a 3.6+ channel/build first, and wait
#    for the operator to serve the v3 CRDs (a listed version is not necessarily
#    served — filter for the served ones):
kubectl get crd datascienceclusters.datasciencecluster.opendatahub.io \
  -o jsonpath='{.spec.versions[?(@.served==true)].name}'   # must list v3

# 2. If your values file sets components.trainingoperator or
#    components.kserve.dsc.wva, remove those keys first — they fail the
#    render even when set to Removed (the migration table's Fails rows).
#    Upgrade with the rest of your values file unchanged, repeating any
#    --set overrides from your original install. operator.type matters
#    most: a --set override lives only in the release, and the chart
#    default is odh — a rhoai release upgraded without repeating it
#    silently switches to the opendatahub operator (and its namespace
#    defaults):
case "${OPERATOR_TYPE}" in odh|rhoai) ;; *) echo "invalid OPERATOR_TYPE" >&2; exit 1;; esac
helm upgrade --install "${OPERATOR_TYPE}" ./charts/rhai-on-openshift-chart \
  -n "${OPERATOR_TYPE}-gitops" --set "operator.type=${OPERATOR_TYPE}" \
  -f my-values.yaml

# 3. Verify: the rendered DSC keeps your value (no CEL immutability conflict):
helm get manifest "${OPERATOR_TYPE}" -n "${OPERATOR_TYPE}-gitops" | \
  grep -A2 'aiHub:'   # instancesNamespace must equal your previous value
```

Use the release name and namespace of your existing install — the example
follows the [Quick Start](#quick-start) convention (`${OPERATOR_TYPE}` in
`${OPERATOR_TYPE}-gitops`); `make helm-install-verify`, for instance, installs
the release `odh` in `opendatahub-gitops`.

Expected result: `modelregistry.dsc.registriesNamespace: odh-model-registry`
renders as `spec.components.aiHub.instancesNamespace: odh-model-registry` —
unchanged from what the operator already owns, so the CEL immutability check
passes and the upgrade applies cleanly.

The repo also provides a repeatable install-and-verify target (requires a live
cluster): `make helm-install-verify`.

This target layers `test/values-e2e.yaml` over the component values on every Helm
install/upgrade. It pins ODH/RHOAI related images through the operator's Subscription
`config.env`. Override the file with `HELM_E2E_VALUES_FILE=/path/to/values.yaml`.

The `Update OCP E2E Images` workflow refreshes these pins from
`opendatahub-io/opendatahub-operator`'s `main/manifests-config.yaml` through an
automated PR, daily or on an `operator-manifest-update` dispatch. To refresh locally:

```bash
bash charts/rhai-on-openshift-chart/scripts/update-e2e-images.sh /path/to/manifests-config.yaml
```

### Dependencies

Operators that can be installed. Use tri-state `enabled` field:

| Value | Behavior |
|-------|----------|
| `auto` | Install if required by an enabled component (default) |
| `true` | Always install |
| `false` | Never install (user has it already) |

| Dependency | Description | Own Dependencies |
|------------|-------------|------------------|
| `certManager` | Cert Manager operator | - |
| `leaderWorkerSet` | Leader Worker Set operator | certManager |
| `jobSet` | Job Set operator | - |
| `rhcl` | RHCL (Kuadrant) operator | certManager, leaderWorkerSet |
| `kueue` | Kueue operator | certManager |
| `customMetricsAutoscaler` | Custom Metrics Autoscaler (KEDA) | - |
| `clusterObservability` | Cluster Observability operator | opentelemetry |
| `opentelemetry` | OpenTelemetry operator | - |
| `tempo` | Tempo operator | opentelemetry |
| `loki` | Loki operator | - |
| `nfd` | Node Feature Discovery (required for GPU support) | - |
| `nvidiaGPUOperator` | NVIDIA GPU Operator (required for GPU support) | nfd |

The COO OperatorGroup defaults to `openshift-cluster-observability-operator`, matching
the RHACM observability addon. When RHACM owns COO, set
`dependencies.clusterObservability.enabled: false` after coordinating the ownership
handoff. See the [COO ownership and migration guide](../../docs/migrations/3.5-3.6-migration.md)
for existing installations and obsolete OperatorGroup cleanup.

### Example: Enable kserve

```yaml
# values.yaml
components:
  kserve:
    # Dependencies are enabled by default, only specify to override
    # dependencies:
    #   certManager: true
    #   leaderWorkerSet: true
    #   jobSet: true
    #   rhcl: true
    #   customMetricsAutoscaler: true
    dsc:
      managementState: Managed
# Dependencies certManager, leaderWorkerSet, jobSet, rhcl, customMetricsAutoscaler
# will be auto-installed because kserve is Managed
```

### Example: Skip a dependency you already have

```yaml
# values.yaml
components:
  kserve:
    dsc:
      managementState: Managed

dependencies:
  certManager:
    enabled: false  # I already have cert-manager installed
```

### Example: Install a dependency without a component

```yaml
# values.yaml
components:
  kserve:
    dsc:
      managementState: Managed

dependencies:
  certManager:
    enabled: true  # Force install even though no component needs it
```

### Example: Enable kueue with custom spec

```yaml
# values.yaml
components:
  kueue:
    dsc:
      managementState: Unmanaged

dependencies:
  kueue:
    enabled: auto
    config:
      # spec accepts any fields supported by the Kueue CR
      spec:
        managementState: Managed
        config:
          integrations:
            frameworks:
              - Deployment
              - Pod
              - PyTorchJob
```

### Example: Enable RHCL with TLS

To enable TLS for Authorino, first deploy with kserve enabled:

```yaml
# values.yaml
components:
  kserve:
    dsc:
      managementState: Managed

dependencies:
  rhcl:
    enabled: auto
    config:
      # Kuadrant CR spec (optional)
      spec: {}
```

Then run the TLS preparation script after the Kuadrant operator has created the Authorino resource:

```bash
./scripts/prepare-authorino-tls.sh
```

### Example: Pin operator to specific version

By default, operators install the latest version available in their channel. To pin an operator to a specific version:

```yaml
# values.yaml
dependencies:
  rhcl:
    enabled: auto
    olm:
      channel: stable
      version: v1.2.1  # Pin to specific version
```

**How it works:**
- **Without `version`**: OLM installs the latest operator version from the channel and upgrades automatically
- **With `version`**: OLM installs the specified version (`startingCSV: rhcl-operator.v1.2.1`) and **automatically sets `installPlanApproval: Manual`** to prevent automatic upgrades
- The version must exist in the specified channel or the subscription will fail

**Install Plan Approval Logic:**
1. **Only `installPlanApproval` set**: Uses the specified approval mode
2. **Only `version` set**: Auto-sets `installPlanApproval: Manual` to lock the version
3. **Both `version` and `installPlanApproval` set**: Uses both (useful for minimum version scenarios)
4. **Neither set**: Explicitly sets `installPlanApproval: Automatic`

**Example - Override to allow upgrades despite version pinning:**
```yaml
dependencies:
  rhcl:
    olm:
      version: v1.2.1  # Minimum version
      installPlanApproval: Automatic  # Still allow auto-upgrades
```

**Use cases:**
- Testing with a known-good version
- Ensuring consistent deployments across environments
- Preventing automatic upgrades to newer versions
- Setting a minimum version while still allowing upgrades

## Values Reference

### Global Settings

```yaml
# Deployment profile: default (all Removed), rhaii, maas
# Explicit managementState values override the profile.
profile: default

# Skip CRD existence checks (required for ArgoCD; renders all CRs upfront)
skipCrdCheck: false

# OLM settings for operator subscriptions
olm:
  installPlanApproval: Automatic
  source: redhat-operators
  sourceNamespace: openshift-marketplace

# Common labels for all resources
labels: {}
```

### Components

Components configure the DataScienceCluster (DSC) and trigger automatic dependency installation.

```yaml
components:
  kserve:
    dependencies:
      certManager: true       # explicitly enable (same as default)
      customMetricsAutoscaler: false  # disable this dependency for kserve
    dsc:
      managementState: Managed  # Managed | Removed (default: Removed)
      rawDeploymentServiceConfig: Headless  # Headless | Headed
      nim:
        managementState: Managed  # NVIDIA NIM integration
  kueue:
    dsc:
      managementState: Unmanaged  # Unmanaged | Removed (default: Removed)

  aipipelines:
    dsc:
      managementState: Managed  # Managed | Removed (default: Removed)

  aiHub:
    dsc:
      managementState: Managed
      instancesNamespace: my-custom-namespace  # overrides operator-type default

  workbenches:
    dsc:
      managementState: Managed
      workbenchNamespace: my-workbench-ns  # overrides operator-type default
```

All components default to `Removed`. When set to `Managed` or `Unmanaged`, the component's dependencies are auto-enabled.

Components with operator-type-specific defaults (like `aiHub` and `workbenches`) will use appropriate namespace values based on whether you're using `odh` or `rhoai` operator type, unless explicitly overridden.

#### How Component Dependencies Work

Each component has a `dependencies` map with **boolean toggles** that control which operators the component will trigger for installation. Dependencies can be required or optional - set them to `false` if you don't need a specific feature.

| Value | Meaning |
|-------|---------|
| `true` | Enable this dependency for the component (default for listed deps) |
| `false` | Disable this dependency - won't be installed for this component |

This is different from the top-level `dependencies.<name>.enabled` field which uses tri-state (`auto`/`true`/`false`).

**The dependency resolution flow:**

1. Component is active (managementState = `Managed` or `Unmanaged`)
2. Component's `dependencies.<dep>` is `true` (or not set, using default)
3. Top-level `dependencies.<dep>.enabled` is `auto` or `true`
4. → Dependency operator gets installed

**Example**: Disable an optional dependency you don't need:

```yaml
components:
  kserve:
    dependencies:
      customMetricsAutoscaler: false  # don't need autoscaling, skip KEDA
    dsc:
      managementState: Managed
# certManager, leaderWorkerSet, jobSet, rhcl will still be auto-installed
# customMetricsAutoscaler will NOT be installed (unless another component needs it)
```

**Example**: You already have cert-manager pre-installed:

```yaml
components:
  kserve:
    dsc:
      managementState: Managed

dependencies:
  certManager:
    enabled: false  # skip installation, I already have it
```

### Dependencies

To configure dependencies, refer to the [api docs](api-docs.md).

## ArgoCD Usage

This chart works with ArgoCD but requires specific configuration:

### Why `skipCrdCheck: true` is required

ArgoCD renders Helm templates **without cluster access**, so the `lookup` function (used to check if CRDs exist) always returns empty results. You must set `skipCrdCheck: true` to render all CRs upfront.

### Why `SkipDryRunOnMissingResource` is required

ArgoCD performs dry-run validation before applying resources. CRs whose CRDs don't exist yet will fail validation. The `SkipDryRunOnMissingResource=true` sync option skips dry-run for these resources.

### Example ArgoCD Application

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: rhoai-dependencies
spec:
  project: default
  source:
    repoURL: https://github.com/your-org/odh-gitops
    targetRevision: main
    path: charts/rhai-on-openshift-chart
    helm:
      values: |
        skipCrdCheck: true
        components:
          kserve:
            dsc:
              managementState: Managed
  destination:
    server: https://kubernetes.default.svc
    namespace: rhoai-system
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - SkipDryRunOnMissingResource=true
```

ArgoCD automatically retries failed resources, so after operators install their CRDs, subsequent syncs will successfully apply the CRs.

### Enable Authorino TLS in ArgoCD

Since the Kuadrant operator automatically creates the Authorino resource, enabling TLS requires a manual step:

```bash
kubectl annotate svc/authorino-authorino-authorization \
    service.beta.openshift.io/serving-cert-secret-name=authorino-server-cert \
    -n kuadrant-system
```

Once the secret is created, set `dependencies.rhcl.config.tlsEnabled` to `true` in the ArgoCD application values.

## Troubleshooting

### CRs not being created

If CR resources (Kueue, Kuadrant, etc.) are not being created:

1. Check if the operator is installed and ready:
   ```bash
   kubectl get csv -A | grep kueue
   ```

2. Check if the CRD exists:
   ```bash
   kubectl get crd kueues.kueue.openshift.io
   ```

3. Run `helm upgrade` again - CRs are skipped until CRDs exist.

### Dependency not being installed

If a dependency is not being installed:

1. Check if the component that requires it is enabled
2. Check if the dependency is explicitly set to `false`
3. Verify the dependency is in the component's dependency map

### Upgrade fails because object fields are modified

If you see the following error:

```txt
Error: UPGRADE FAILED: conflict occurred while applying object ...
```

It is an Helm Server-Side Apply (SSA) field ownership issue. The error indicates that Helm is trying to update a field that is not owned by the Helm chart.
To fix it, you can force conflicts resolution by adding the `--force-conflicts` flag to the helm upgrade command.
