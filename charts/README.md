# xKS Operator Helm Charts

Helm charts for deploying dependent operators on vanilla Kubernetes (xKS) clusters without OLM.
These charts are extracted from Red Hat operator bundles and deploy operators with hardcoded namespaces.

## Charts

| Chart | Version | Namespace | Description |
|-------|---------|-----------|-------------|
| `cert-manager-operator` | v1.18.1 | `cert-manager-operator` / `cert-manager` | Red Hat cert-manager Operator |
| `gateway-api` | v1.4.0 | cluster-scoped | [Kubernetes Gateway API](https://github.com/kubernetes-sigs/gateway-api) CRDs |
| `lws-operator` | 1.0 | `openshift-lws-operator` | Leader-Worker-Set Operator |
| `sail-operator` | 3.2.1 (Istio up to v1.27.3) | `istio-system` | Red Hat Sail (Istio) Operator |

## Pre-Install Steps

### Infrastructure CRD and CR (required for cert-manager-operator)

The cert-manager operator expects an OpenShift Infrastructure CR. On vanilla Kubernetes, this CRD and CR don't exist, so you need to create both before installing the chart:

```bash
# 1. Install the Infrastructure CRD (OpenShift API, cluster-scoped)
kubectl apply -f https://raw.githubusercontent.com/openshift/api/master/config/v1/zz_generated.crd-manifests/0000_10_config-operator_01_infrastructures-CustomNoUpgrade.crd.yaml

# 2. Create the Infrastructure CR
kubectl apply -f - <<EOF
apiVersion: config.openshift.io/v1
kind: Infrastructure
metadata:
  name: cluster
spec: {}
status:
  controlPlaneTopology: HighlyAvailable
  infrastructureTopology: HighlyAvailable
  platform: None
EOF
```

### Auth Reader RoleBinding (required for lws-operator)

Kubernetes addon API servers need to read the `extension-apiserver-authentication` configmap in `kube-system` for authentication delegation (see [apiserver auth docs](https://github.com/kubernetes-sigs/apiserver-builder-alpha/blob/master/docs/concepts/auth.md)). On OpenShift, all authenticated service accounts already have this access. On vanilla Kubernetes, this binding doesn't exist and operators like LWS will crash on startup. Create it once for the cluster before installing:

```bash
kubectl apply -f - <<EOF
apiVersion: rbac.authorization.k8s.io/v1
kind: RoleBinding
metadata:
  name: extension-apiserver-authentication-reader-all
  namespace: kube-system
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: Role
  name: extension-apiserver-authentication-reader
subjects:
  - apiGroup: rbac.authorization.k8s.io
    kind: Group
    name: system:authenticated
EOF
```

## Installation

```bash
helm install cert-manager-operator charts/cert-manager-operator/
helm install gateway-api charts/gateway-api/
helm install lws-operator charts/lws-operator/
helm install sail-operator charts/sail-operator/
```

Each operator chart creates its own namespace from `values.yaml` defaults. The `gateway-api` chart is cluster-scoped (CRDs only) and does not create a namespace.

## Post-Install Steps

### 1. Pull Secrets (if using registry.redhat.io images)

If your cluster does not have access to `registry.redhat.io`, create a pull secret in each operator namespace and patch the service accounts.

**Create pull secrets** (using a pull secret file, e.g. `~/pull-secret.txt`):

```bash
kubectl create secret generic redhat-pull-secret \
  --from-file=.dockerconfigjson=/path/to/pull-secret.txt \
  --type=kubernetes.io/dockerconfigjson \
  -n cert-manager-operator

kubectl create secret generic redhat-pull-secret \
  --from-file=.dockerconfigjson=/path/to/pull-secret.txt \
  --type=kubernetes.io/dockerconfigjson \
  -n openshift-lws-operator

kubectl create secret generic redhat-pull-secret \
  --from-file=.dockerconfigjson=/path/to/pull-secret.txt \
  --type=kubernetes.io/dockerconfigjson \
  -n istio-system
```

**Patch service accounts:**

```bash
kubectl patch sa cert-manager-operator-controller-manager -n cert-manager-operator \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'

kubectl patch sa openshift-lws-operator -n openshift-lws-operator \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'

kubectl patch sa servicemesh-operator3 -n istio-system \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'
```

Restart pods to pick up the secrets:

```bash
kubectl delete pod --all -n cert-manager-operator
kubectl delete pod --all -n openshift-lws-operator
kubectl delete pod --all -n istio-system
```

### 2. CertManager CR

After the cert-manager operator is running, create the CertManager CR to trigger operand deployment:

```bash
kubectl apply -f - <<EOF
apiVersion: operator.openshift.io/v1alpha1
kind: CertManager
metadata:
  name: cluster
spec:
  managementState: Managed
  logLevel: Normal
  operatorLogLevel: Normal
EOF
```

Then create pull secrets for the operand namespace and patch operand service accounts:

```bash
# Create pull secret in cert-manager namespace (created by the operator)
kubectl create secret generic redhat-pull-secret \
  --from-file=.dockerconfigjson=/path/to/pull-secret.txt \
  --type=kubernetes.io/dockerconfigjson \
  -n cert-manager

# Patch operand service accounts
kubectl patch sa cert-manager -n cert-manager \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'
kubectl patch sa cert-manager-cainjector -n cert-manager \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'
kubectl patch sa cert-manager-webhook -n cert-manager \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'
```

### 3. Istio CR (sail-operator)

After the sail operator is running, create the Istio CR to deploy istiod:

```bash
kubectl apply -f - <<EOF
apiVersion: sailoperator.io/v1
kind: Istio
metadata:
  name: default
  namespace: istio-system
spec:
  namespace: istio-system
  version: v1.27-latest
  values:
    pilot:
      env:
        PILOT_ENABLE_GATEWAY_API: "true"
        PILOT_ENABLE_GATEWAY_API_DEPLOYMENT_CONTROLLER: "true"
        PILOT_ENABLE_GATEWAY_API_STATUS: "true"
        ENABLE_GATEWAY_API_INFERENCE_EXTENSION: "true"
    meshConfig:
      accessLogFile: /dev/stdout
      defaultConfig:
        proxyMetadata:
          ENABLE_GATEWAY_API_INFERENCE_EXTENSION: "true"
EOF
```

Then patch the istiod service account with the pull secret:

```bash
kubectl patch sa istiod -n istio-system \
  -p '{"imagePullSecrets": [{"name": "redhat-pull-secret"}]}'

kubectl delete pod -l app=istiod -n istio-system
```

### 4. Fix Webhook Reconciliation Loop (sail-operator)

On vanilla Kubernetes, the sail-operator enters an infinite reconciliation loop because istiod injects `caBundle` into webhook configurations, which triggers the operator to reconcile again endlessly. After the Istio CR is ready and istiod is running, annotate the webhooks:

```bash
# Wait for istiod to be ready, then run:
kubectl annotate mutatingwebhookconfiguration istio-sidecar-injector sailoperator.io/ignore=true --overwrite
kubectl annotate validatingwebhookconfiguration istio-validator-istio-system sailoperator.io/ignore=true --overwrite
```

## Updating Charts

### Operator charts (bundle-derived)

Each operator chart under `charts/dependencies/` includes an `update-bundle.sh` script that extracts fresh manifests from Red Hat operator bundles.

**Prerequisites:** `podman`, `python3`, `pyyaml`, and registry authentication:

```bash
podman login registry.redhat.io
```

**Update commands:**

```bash
./charts/dependencies/cert-manager-operator/scripts/update-bundle.sh v1.18.1
./charts/dependencies/lws-operator/scripts/update-bundle.sh 1.0
./charts/dependencies/sail-operator/scripts/update-bundle.sh 3.2.1
```

The scripts:
1. Pull the operator bundle image from `registry.redhat.io`
2. Extract manifests using [`olm-extractor`](https://github.com/lburgazzoli/olm-extractor)
3. Split into CRDs (`crds/`) and templates (`templates/`), templatizing namespace references
4. Update `bundle.version` in `values.yaml`

**After updating**, review the generated manifests and verify with:

```bash
helm lint charts/dependencies/<chart-name>/
make chart-snapshots
```

### Gateway API chart (CRDs only)

The `gateway-api` chart contains cluster-scoped CRDs downloaded directly from GitHub (not from an operator bundle). Use `update-crds.sh` to update:

```bash
./charts/dependencies/gateway-api/scripts/update-crds.sh v1.4.0
./charts/dependencies/gateway-api/scripts/update-crds.sh v1.4.0 experimental  # for experimental channel
```

The script downloads CRDs from the [kubernetes-sigs/gateway-api](https://github.com/kubernetes-sigs/gateway-api) repository and updates both `values.yaml` and `Chart.yaml` with the new version.

**After updating**, review the generated manifests and verify with:

```bash
helm lint charts/dependencies/gateway-api/
make chart-snapshots
```

### RHAI On XKS Helm Chart

The `rhai-on-xks-helm-chart` generates its templates from the [opendatahub-operator](https://github.com/opendatahub-io/opendatahub-operator) repository using kustomize and [helmtemplate-generator](https://github.com/davidebianchi/helmtemplate-generator). It also generates cloud-specific (Azure, CoreWeave) cloudmanager templates.

**Prerequisites:** `go`, `kustomize`, and access to the ODH `opendatahub-operator` git repo.

**Update from the default branch (rhoai-3.4):**

```bash
./charts/rhai-on-xks-chart/scripts/update-bundle.sh 3.4.0-ea.2
```

**Update from a specific branch:**

```bash
./charts/rhai-on-xks-chart/scripts/update-bundle.sh 3.5.0 --branch rhoai-3.5
```

**Update from a local opendatahub-operator checkout** (skips cloning):

```bash
./charts/rhai-on-xks-chart/scripts/update-bundle.sh v2.19.0 --odh-operator-dir /path/to/opendatahub-operator
```

The script:

1. Clones (or uses a local) opendatahub-operator repo and runs `make manifests-all`
2. Builds kustomize manifests from `config/rhaii/rhoai/default/`
3. Pipes them through `helmtemplate-generator` to produce Helm templates
4. Repeats for each cloudmanager target (Azure, CoreWeave) from `config/cloudmanager/<cloud>/rhoai/`
5. Updates `Chart.yaml` with the new `appVersion`
