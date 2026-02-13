# OpenDataHub - GitOps Repository

This repository provides a GitOps-based approach to deploying and managing OpenDataHub and its dependencies using Kustomize. It serves as a standardized, repeatable, and automated way to configure the complete OpenDataHub stack.

## Table of Contents

- [OpenDataHub - GitOps Repository](#opendatahub---gitops-repository)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
    - [How the Structure Works](#how-the-structure-works)
    - [Dependencies](#dependencies)
      - [Operator Configuration Requirements](#operator-configuration-requirements)
        - [Red Hat Connectivity Link operator](#red-hat-connectivity-link-operator)
          - [Stage 1: Deploy base configuration](#stage-1-deploy-base-configuration)
          - [Stage 2: Enable TLS](#stage-2-enable-tls)
        - [MariaDB Operator](#mariadb-operator)
          - [Installation steps:](#installation-steps)
      - [Adding New Dependencies](#adding-new-dependencies)
  - [Quick Start](#quick-start)
    - [Prerequisites](#prerequisites)
  - [Installation Methods](#installation-methods)
    - [Installation instructions](#installation-instructions)
    - [Installation with ArgoCD](#installation-with-argocd)
      - [Prerequisites](#prerequisites-1)
      - [Installation instructions](#installation-instructions-1)
      - [Install All Dependencies](#install-all-dependencies)
      - [Install Specific Dependencies](#install-specific-dependencies)
    - [Installation with CLI](#installation-with-cli)
      - [Install All Dependencies](#install-all-dependencies-1)
    - [Install Specific Dependencies](#install-specific-dependencies-1)
    - [Install a Subset of Dependencies](#install-a-subset-of-dependencies)
  - [Usage Guidelines](#usage-guidelines)
    - [For Administrators](#for-administrators)
  - [Release Strategy](#release-strategy)
    - [Release Workflow](#release-workflow)

## Overview

This repository addresses OpenDataHub dependencies that are treated as **administrator-owned resources**. It provides a template for deploying these prerequisites in a standardized way, simplifying the administrator's workflow by providing a single source of truth for the entire OpenDataHub stack.

This repository works with GitOps tools (ArgoCD, Flux, etc.).

### How the Structure Works

The repository is designed to be applied in **layers**, providing flexibility in deployment:

1. **Granular Installation**: Each dependency or component has its own `kustomization.yaml` and can be applied independently.
2. **Grouped Installation**: Top-level folders contain `kustomization.yaml` files that include all items within them.
3. **Composition**: Each component is self-contained and includes its required dependencies.

### Dependencies

| Operator                           | Purpose                                     | Namespace | Used By                  | Operators Required |
|------------------------------------|---------------------------------------------|-----------|------------------------------|-------------|
| **Cert-Manager**                   | Certificate management and TLS provisioning | `cert-manager-operator` | Model Serving (Kueue, Ray)   | |
| **Kueue**                          | Job queue for distributed workloads         | `openshift-kueue-operator` | Model Serving (Ray), Trainer | Cert-Manager |
| **Cluster Observability Operator** | Cluster observability and monitoring        | `openshift-cluster-observability-operator` | Monitoring                   | |
| **OpenTelemetry Product**          | OpenTelemetry product                       | `openshift-opentelemetry-operator` | Monitoring                   | |
| **Leader Worker Set** | Deploy a LWS in OpenShift for distributed inference workflows | `openshift-lws-operator` | Model Server | Cert-Manager |
| **Job Set Operator**               | Job management as a unit                    | `openshift-jobset-operator` | Trainer                      | |
| **Custom Metrics Autoscaler** | Event-driven autoscaler based on KEDA | `openshift-keda` | Model Serving | |
| **Tempo Operator** | Distributed tracing backend | `openshift-tempo-operator` | Tracing infrastructure | |
| **Red Hat Connectivity Link** | Multicloud application connectivity and API management | `kuadrant-system` | Model Serving (KServe) | Leader Worker Set, Cert-Manager |
| **MariaDB Operator** | MariaDB for OpenShift | `mariadb-operator` | TrustyAI (optional, only if using database mode) | |
| **Node Feature Discovery** | Detects hardware features and capabilities of nodes | `openshift-nfd` | LlamaStack Operator | |
| **NVIDIA GPU Operator** | Enables GPU-accelerated workloads on NVIDIA hardware | `nvidia-gpu-operator` | Model Serving, LlamaStack Operator | Node Feature Discovery |

#### Operator Configuration Requirements

Some operators require additional configuration. Below are the configuration requirements for each operator:

##### Red Hat Connectivity Link operator

Additional configuration is needed to enable TLS for Authorino. This is done in two stages:

###### Stage 1: Deploy base configuration

1. Apply RHCL base configuration (no TLS enabled):
   ```bash
   kubectl apply -k configurations/rhcl-operator
   ```

2. Verify that Kuadrant CR and Authorino CR exist and are Ready:
   ```bash
   kubectl get kuadrant -n <kuadrant-namespace>
   kubectl get authorino -n <kuadrant-namespace>
   ```

###### Stage 2: Enable TLS

3. Run the preparation script to annotate the Service, generate the TLS certificate Secret, and update the kustomization.yaml for RHCL:
   ```bash
   make prepare-authorino-tls KUADRANT_NS=<kuadrant-namespace>
   ```

4. Re-apply the configuration to enable TLS for Authorino:
   ```bash
   kubectl apply -k configurations/rhcl-operator
   ```

5. Verify that Authorino has TLS enabled:
   ```bash
   kubectl get authorino authorino -n <kuadrant-namespace> -o jsonpath='{.spec.listener.tls}'
   ```

##### MariaDB Operator

MariaDB operator is an optional dependency in case the user is planning to use TrustyAI with Database mode.
As such, it is not listed by default among other dependencies in `dependencies/operators/kustomization.yaml`, and has specific installation steps.

**Due to TLS issues with newer MariaDB versions, the recommended version is v0.29**

###### Installation steps:

1. Apply MariaDB Operator resources using:
  ```bash
  kubectl apply -k dependencies/operators/maria-db 
  ```

2. Get InstallPlan name for MariaDB Operator v0.29 using:
  ```bash
  kubectl get installplan -n mariadb-operator | grep v0.29 | sed 's/ .*//'
  ```

3. Approve the InstallPlan using (insert the previously-obtained InstallPlan name):
  ``` bash
  kubectl patch installplan <install-plan-name> -n mariadb-operator --type merge -p '{"spec":{"approved":true}}'
  ```

4. Wait for the MariaDB Operator installation to complete. Verify that the operator pod is running using:
  ```bash
  kubectl get pods -n mariadb-operator -l control-plane=controller-manager
  ```

#### Adding New Dependencies

To add a new dependency, follow the [Contributing](CONTRIBUTING.md#add-a-new-dependency-operator) guide.

## Quick Start

### Prerequisites

- OpenShift cluster (version 4.19 or later)
- `kubectl` or `oc` CLI installed
- Cluster admin permissions
- Kustomize v5 or later (optional - `kubectl` has built-in Kustomize support)

## Installation Methods

### Installation instructions

```bash
# 1. Clone the repository
git clone https://github.com/opendatahub-io/odh-gitops.git
cd odh-gitops

# 2. Modify as needed

# 3. Follow the desired tool installation instructions,
#    using the correct branch matching your desired
#    OpenDataHub version (e.g. odh-3.0)
```

### Installation with ArgoCD

#### Prerequisites

- ArgoCD installed
- Cluster admin permissions
- The ArgoCD instance needs permissions to handle cluster configuration. Follow [this documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_gitops/1.19/html/declarative_cluster_configuration/configuring-an-openshift-cluster-by-deploying-an-application-with-cluster-configurations#gitops-additional-permissions-for-cluster-config_configuring-an-openshift-cluster-by-deploying-an-application-with-cluster-configurations). Additional permissions needed are:
  - all actions on kueues.kueue.openshift.io
  - all actions on kuadrants.kuadrant.io

#### Installation instructions

To install the repository with ArgoCD, create a new ArgoCD application and point it to the repository with the desired branch.
To ensure it will work, since it uses custom resources whose definitions are installed by the operators by OLM in a second step, you need to skip dry run on missing resources in the Application resource.

```yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: ...
spec:
  syncPolicy:
      syncOptions:
        - SkipDryRunOnMissingResource=true
```

#### Install All Dependencies

Create an application, setting the sync policy to skip dry run on missing resources, and point to the base directory `kustomization.yaml`.
In this way, all dependencies will be installed automatically.

#### Install Specific Dependencies

To install specific dependencies, open [`dependencies/operators/kustomization.yaml`](dependencies/operators/kustomization.yaml) and comment out the dependencies you don't need.
Do the same for [`configurations/kustomization.yaml`](configurations/kustomization.yaml).

For example, if the Kueue operator is not needed, comment it out like this in [`dependencies/operators/kustomization.yaml`](dependencies/operators/kustomization.yaml):

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

components:
  - ../../components/operators/cert-manager
  # - ../../components/operators/kueue-operator
```

After that, setup the application to point to the base directory `kustomization.yaml` file.

### Installation with CLI

#### Install All Dependencies

```bash
# Install all dependencies
kubectl apply -k dependencies

# Wait some seconds to let the operators install

# Install operator configurations
kubectl apply -k configurations
```

### Install Specific Dependencies

```bash
kubectl apply -k dependencies/operators/cert-manager
kubectl apply -k dependencies/operators/kueue-operator

# Wait some seconds to let the operators install

# Install specific operator configurations
kubectl apply -k configurations/kueue-operator
```

### Install a Subset of Dependencies

You can modify `dependencies/operators/kustomization.yaml` to comment out dependencies you don't need.
For example, if the Kueue operator is not needed, comment it out like this:

```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

components:
  - ../../components/operators/cert-manager
  # - ../../components/operators/kueue-operator
```

If you need the Kueue operator later, uncomment it and apply the changes:

```bash
# Install the dependencies
kubectl apply -k dependencies/

# Install the operator configurations
kubectl apply -k configurations/
```

## Usage Guidelines

### For Administrators

1. **Fork or Clone** this repository as a starting point for your organization
2. **Select the Branch** matching your target OpenDataHub version (e.g., `odh-3.0`)
3. **Customize** the configurations for your specific environment
4. **Test** thoroughly in a non-production environment
5. **Maintain** your fork with updates and customizations
6. **Apply** using your GitOps tool (ArgoCD, Flux, etc.) or `kubectl`

## Release Strategy

- **No Formal Releases**: This repository does not have official releases. Users are expected to clone or fork the repository and use it as a basis for their own configurations.
- **Branch per OpenDataHub and RHOAI Version**: Each minor version of OpenDataHub/RHOAI has a dedicated branch (e.g., `odh-3.x`, `rhoai-3.x`). This will simplify the fix or updates of the specific minor version.
- **Tag**: Each z-stream release has a dedicated tag (e.g., `odh-3.0.0`, `rhoai-3.0.0`) to ensure compatibility.
- **Version Selection**: Always select the branch that corresponds to your target OpenDataHub/RHOAI version.

### Release Workflow

The release workflow is as follows:

1. On the day of the code freeze, the release branch is created from the main branch.
2. Changes in main can be cherry-picked into the release branch if needed.
3. Since the chart depends on the OLM channel, if a new version uses a different OLM channel, the chart will need to be updated after the OLM is released.
4. The GA date, once the release is done, the repository will be tagged with the corresponding tag.
