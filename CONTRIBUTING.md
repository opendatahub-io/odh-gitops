# Contributing to OpenDataHub GitOps Repository

Thank you for your interest in contributing to the OpenDataHub GitOps repository! This document provides guidelines and instructions for contributing to this project.

## Table of Contents

- [Contributing to OpenDataHub GitOps Repository](#contributing-to-opendatahub-gitops-repository)
  - [Table of Contents](#table-of-contents)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
  - [Add a New Kustomize Dependency Operator](#add-a-new-kustomize-dependency-operator)
    - [Step 1: Create a New Operator Component](#step-1-create-a-new-operator-component)
    - [Step 2: Create Required Manifests](#step-2-create-required-manifests)
    - [Step 3: Create Dependency Operator Directory](#step-3-create-dependency-operator-directory)
    - [Step 4: Update Operators Parent Kustomization](#step-4-update-operators-parent-kustomization)
    - [Step 5: Add Base Configuration for Your Operator](#step-5-add-base-configuration-for-your-operator)
    - [Step 6: Update Configurations Parent Kustomization](#step-6-update-configurations-parent-kustomization)
    - [Step 7: Update Scripts](#step-7-update-scripts)
      - [Verify Dependencies Script](#verify-dependencies-script)
      - [Remove Dependencies Script](#remove-dependencies-script)
    - [Step 8: Document the Operator](#step-8-document-the-operator)
    - [Step 9: Test Your Changes](#step-9-test-your-changes)
  - [Contributing to the Helm Chart](#contributing-to-the-helm-chart)
    - [Adding a New Dependency to the Helm Chart](#adding-a-new-dependency-to-the-helm-chart)
      - [Step 1: Add Values Configuration](#step-1-add-values-configuration)
      - [Step 2: Update Dependency Mappings](#step-2-update-dependency-mappings)
      - [Step 3: Create Dependency Templates](#step-3-create-dependency-templates)
      - [Step 4: Update JSON Schema](#step-4-update-json-schema)
      - [Step 5: Update Documentation](#step-5-update-documentation)
    - [Adding a New Component to the Helm Chart](#adding-a-new-component-to-the-helm-chart)
      - [Step 1: Add Component Configuration](#step-1-add-component-configuration)
      - [Step 2: Update Component → Dependency Mapping](#step-2-update-component--dependency-mapping)
      - [Step 3: Update DataScienceCluster Template](#step-3-update-datasciencecluster-template)
      - [Step 4: Update JSON Schema](#step-4-update-json-schema-1)
      - [Step 5: Update Documentation](#step-5-update-documentation-1)
    - [Testing Helm Chart Changes](#testing-helm-chart-changes)
  - [Testing Your Changes](#testing-your-changes)
    - [Local Validation](#local-validation)
  - [Pull Requests](#pull-requests)
    - [Workflow](#workflow)
    - [Open a Pull Request](#open-a-pull-request)
    - [Commit Messages](#commit-messages)

## Getting Started

### Prerequisites

- Git
- `kubectl` or `oc` CLI
- Access to an OpenShift cluster (for testing)
- Kustomize v5 or later

## Add a New Kustomize Dependency Operator

When adding a new dependency operator required by OpenDataHub:

### Step 1: Create a New Operator Component

Create a new directory under `components/operators/` named after your operator:

```bash
mkdir -p components/operators/your-operator
```

### Step 2: Create Required Manifests

Create the files required to install the dependency operator in your operator directory, including a `kustomization.yaml` file.

> [!NOTE]
> Do not set the namespace name in the `kustomization.yaml` file, but set it as a string in the individual resource files where needed.

### Step 3: Create Dependency Operator Directory

Create a new directory under `dependencies/operators/` named after your operator:

```bash
mkdir -p dependencies/operators/your-operator
```

Add a `kustomization.yaml` file to the directory, for example:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

components:
  - ../../../components/operators/your-operator/
```

Add patches if needed.

If your operator depends on other operators, add them to the `components` list.
For an example, see the [kueue operator](dependencies/operators/kueue-operator/kustomization.yaml) directory.

### Step 4: Update Operators Parent Kustomization

Add your operator to `dependencies/operators/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

components:
  - ../../../components/operators/cert-manager/
  - ...
  - ../../../components/operators/your-operator/ # Add this line
```

### Step 5: Add Base Configuration for Your Operator

If your operator needs a configuration which depends on CRDs installed by OLM, you can add it to the `configurations/your-operator` folder.

For an example, see the [Kueue configuration](configurations/kueue-operator/) directory.

### Step 6: Update Configurations Parent Kustomization

Add your operator to `configurations/kustomization.yaml`:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - ...
  - your-operator
```

### Step 7: Update Scripts

Update the maintenance scripts to support your new operator.

#### Verify Dependencies Script

Add your operator to [`scripts/verify-dependencies.sh`](./scripts/verify-dependencies.sh) to enable automated verification.

The script performs the following checks:

- Verifies the operator's Subscription is in the `Succeeded` phase
- Confirms the operator's ClusterServiceVersion (CSV) is in the `Succeeded` phase
- Optionally validates additional resources managed by the operator

You can extend the verification logic to include custom health checks for resources created by your operator.

#### Remove Dependencies Script

Only update [`scripts/remove-dependencies.sh`](./scripts/remove-dependencies.sh) if your operator requires special cleanup steps during uninstallation (e.g., removing CRDs, finalizers, or dependent resources that block deletion).

For most operators, the default cleanup process is sufficient, and no changes are needed.

### Step 8: Document the Operator

Add documentation about your operator:

1. Update `README.md` with operator information.
2. Add any special configuration requirements.

### Step 9: Test Your Changes

See [Testing Your Changes](#testing-your-changes) section below.

## Contributing to the Helm Chart

The repository includes a Helm chart (`chart/`) that provides an alternative installation method alongside Kustomize. When adding or modifying dependencies, you should also update the Helm chart.

### Adding a New Dependency to the Helm Chart

When adding a new dependency operator, follow these steps:

#### Step 1: Add Values Configuration

Add your dependency to `chart/values.yaml` under the `dependencies` section:

```yaml
dependencies:
  yourOperator:
    # -- Enable your-operator: auto (if needed), true (always), false (never)
    enabled: auto
    olm:
      channel: stable
      name: your-operator
      namespace: your-operator-namespace
    config: # optional
      # -- YourOperator CR spec (user can add any fields supported by the CR)
      spec: {}
```

#### Step 2: Update Dependency Mappings

If your dependency is required by a component or another dependency, update `chart/templates/definitions/_dependencies.tpl`:

```yaml
# Component → Dependency mapping
{{- define "rhoai-dependencies.componentDeps" -}}
kserve:
  - certManager
  - yourOperator  # Add if kserve requires it
...
{{- end }}

# Dependency → Dependency mapping (transitive dependencies)
{{- define "rhoai-dependencies.dependencyDeps" -}}
yourOperator:
  - certManager   # List dependencies your operator requires
...
{{- end }}
```

#### Step 3: Create Dependency Templates

Create a new directory `chart/templates/dependencies/your-operator/` with:

**operator.yaml** - OLM installation:

```yaml
{{- $dep := .Values.dependencies.yourOperator -}}
{{- $shouldInstall := include "rhoai-dependencies.shouldInstall" (dict "dependencyName" "yourOperator" "dependency" $dep "dependencies" .Values.dependencies "components" .Values.components) -}}
{{- if eq $shouldInstall "true" }}
{{- $installType := include "rhoai-dependencies.installationType" (dict "dependency" $dep "global" .Values.global) -}}
{{- if eq $installType "olm" }}
{{ include "rhoai-dependencies.operator.olm" (dict "name" $dep.olm.name "namespace" $dep.olm.namespace "channel" $dep.olm.channel "root" $) }}
{{- end }}
{{- end }}
```

**config.yaml** (optional) - CR configuration:

```yaml
{{- $dep := .Values.dependencies.yourOperator -}}
{{- $shouldInstall := include "rhoai-dependencies.shouldInstall" (dict "dependencyName" "yourOperator" "dependency" $dep "dependencies" .Values.dependencies "components" .Values.components) -}}
{{- if and (eq $shouldInstall "true") (include "rhoai-dependencies.crdExists" (dict "crdName" "yourresources.your.domain.io" "root" $)) }}
apiVersion: your.domain.io/v1
kind: YourResource
metadata:
  name: cluster
  labels:
    {{- include "rhoai-dependencies.labels" . | nindent 4 }}
{{- with $dep.config.spec }}
spec:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}
```

#### Step 4: Update JSON Schema

Add your dependency to [`chart/values.schema.json`](./chart/values.schema.json) to enable validation.

#### Step 5: Update Documentation

Run `make helm-docs` to regenerate `chart/api-docs.md`.

### Adding a New Component to the Helm Chart

Components are high-level features (like kserve, kueue, aipipelines) that configure the DataScienceCluster and auto-enable their required dependencies.

#### Step 1: Add Component Configuration

Add your component to `chart/values.yaml` under the `components` section:

```yaml
components:
  # -- Your component description
  yourComponent:
    # -- Management state for YourComponent (Managed or Removed)
    managementState: Managed
```

#### Step 2: Update Component → Dependency Mapping

Add the component's dependencies to `chart/templates/definitions/_dependencies.tpl`:

```yaml
{{- define "rhoai-dependencies.componentDeps" -}}
kserve:
  - certManager
  - leaderWorkerSet
  ...
yourComponent:
  - certManager       # List all dependencies your component requires
  - yourOperator
{{- end }}
```

#### Step 3: Update DataScienceCluster Template

Add your component to `chart/templates/operator/datasciencecluster.yaml`:

```yaml
spec:
  components:
    kserve:
      managementState: {{ .Values.components.kserve.managementState }}
    yourComponent:
      managementState: {{ .Values.components.yourComponent.managementState }}
```

#### Step 4: Update JSON Schema

Add your component to `chart/values.schema.json` under the `components` section.

#### Step 5: Update Documentation

1. Update `chart/README.md` with component information
2. Run `make helm-docs` to regenerate `chart/api-docs.md`

### Testing Helm Chart Changes

1. **Lint the chart**:

   ```bash
   helm lint ./chart
   ```

2. **Template locally**:

   ```bash
   helm template ./chart --set global.skipCrdCheck=true
   ```

3. **Update snapshots**:

   ```bash
   make chart-snapshots
   ```

4. **Test on a cluster** (optional):

   ```bash
   helm upgrade --install rhoai ./chart -n opendatahub-gitops --create-namespace
   ```

## Testing Your Changes

Always test your changes before submitting a PR.

### Local Validation

1. **Validate Kustomize Build**:

  Run `make validate` to validate the kustomization files.

2. **Check for YAML Errors**:

   ```bash
   kustomize build . | kubectl apply --dry-run=client -f -
   ```

3. **Validate Installation on a Real Cluster**: Test the operator installation on an actual OpenShift cluster to ensure it works as expected.

## Pull Requests

### Workflow

1. **Fork the Repository:** Create your own fork of the repository to work on your changes.
2. **Create a Branch:** Create your own branch for the feature or bug fix off of the `main` branch.
3. **Work on Your Changes:** Commit often, and ensure Kustomize builds correctly.
4. **Testing:** Make sure to test your changes in a real cluster. See the [Testing Your Changes](#testing-your-changes) section above.
5. **Open a PR Against `main`:** See the PR guidelines below.

### Open a Pull Request

1. **Link to Jira Issue**: Include the Jira issue link in your PR description.
2. **Description**: Provide a detailed description of the changes and what they fix or implement.
3. **Add Testing Steps**: Provide information on how the PR has been tested, and list testing steps for reviewers.
4. **Review Request**: Tag the relevant maintainers or team members for a review. We follow the [Kubernetes review process](https://github.com/kubernetes/community/blob/master/contributors/guide/owners.md#the-code-review-process).
5. **Resolve Feedback**: Be open to feedback and iterate on your changes.

### Commit Messages

We follow the [Conventional Commits](https://www.conventionalcommits.org/) format for writing commit messages. A good commit message should include:

1. **Type:** `fix`, `feat`, `docs`, `chore`, etc. **Note:** All commits except `chore` require an associated Jira issue. Please add a link to your Jira issue.
2. **Scope:** A short description of the area affected.
3. **Summary:** A brief explanation of what the commit does.
