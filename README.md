# Red Hat OpenShift AI - GitOps Repository

This repository provides a GitOps-based approach to deploying and managing Red Hat OpenShift AI and its dependencies using Kustomize. It serves as a standardized, repeatable, and automated way to configure the complete OpenShift AI stack.

## Table of Contents

- [Red Hat OpenShift AI - GitOps Repository](#red-hat-openshift-ai---gitops-repository)
  - [Table of Contents](#table-of-contents)
  - [Overview](#overview)
    - [How the Structure Works](#how-the-structure-works)
    - [Dependencies](#dependencies)
      - [Adding New Dependencies](#adding-new-dependencies)
  - [Quick Start](#quick-start)
    - [Prerequisites](#prerequisites)
  - [Installation Methods](#installation-methods)
    - [Installation instructions](#installation-instructions)
    - [Installation with ArgoCD](#installation-with-argocd)
      - [Install All Dependencies](#install-all-dependencies)
      - [Install Specific Dependencies](#install-specific-dependencies)
    - [Installation with CLI](#installation-with-cli)
      - [Install All Dependencies](#install-all-dependencies-1)
    - [Install Specific Dependencies](#install-specific-dependencies-1)
    - [Install a Subset of Dependencies](#install-a-subset-of-dependencies)
  - [Usage Guidelines](#usage-guidelines)
    - [For Administrators](#for-administrators)
  - [Release Strategy](#release-strategy)

## Overview

This repository addresses OpenShift AI dependencies that are treated as **administrator-owned resources**. It provides a template for deploying these prerequisites in a standardized way, simplifying the administrator's workflow by providing a single source of truth for the entire OpenShift AI stack.

This repository works with GitOps tools (ArgoCD, Flux, etc.).

### How the Structure Works

The repository is designed to be applied in **layers**, providing flexibility in deployment:

1. **Granular Installation**: Each dependency or component has its own `kustomization.yaml` and can be applied independently.
2. **Grouped Installation**: Top-level folders contain `kustomization.yaml` files that include all items within them.
3. **Composition**: Each component is self-contained and includes its required dependencies.

### Dependencies

| Operator                           | Purpose                                     | Namespace | Required By                  | Operators Required |
|------------------------------------|---------------------------------------------|-----------|------------------------------|-------------|
| **Cert-Manager**                   | Certificate management and TLS provisioning | `cert-manager-operator` | Model Serving (Kueue, Ray)   | |
| **Kueue**                          | Job queue for distributed workloads         | `openshift-kueue-operator` | Model Serving (Ray), Trainer | Cert-Manager |
| **Cluster Observability Operator** | Cluster observability and monitoring        | `openshift-cluster-observability-operator` | Monitoring                   | |
| **OpenTelemetry Product**          | OpenTelemetry product                       | `openshift-opentelemetry-operator` | Monitoring                   | |
| **Leader Worker Set** | Deploy a LWS in OpenShift for distributed inference workflows | `openshift-lws-operator` | Model Server | Cert-Manager |
| **Job Set Operator**               | Job management as a unit                    | `openshift-jobset-operator` | Trainer                      | |
| **Custom Metrics Autoscaler** | Event-driven autoscaler based on KEDA | `openshift-keda` | Model Serving | |
| **Tempo Operator** | Distributed tracing backend | `openshift-tempo-operator` | Tracing infrastructure | |

#### Operator Configuration Requirements

Some operators require additional configuration. Below are the configuration requirements for each operator:

##### Tempo Operator

The Tempo Operator requires object storage configuration and a custom resource (**TempoStack** or **TempoMonolithic**) to be created after the operator is installed.

#### Configuration Steps:

1. Follow the [Red Hat Distributed Tracing Platform Documentation](https://docs.redhat.com/en/documentation/openshift_container_platform/4.19/html/distributed_tracing/distr-tracing-tempo-installing) to:
   - Set up object storage (S3, GCS, or Azure)
   - Create the storage secret
   - Create a TempoStack or TempoMonolithic custom resource

2. Place your Tempo configuration manifests in the `configurations/tempo-operator/` directory

3. Create a `kustomization.yaml` file in `configurations/tempo-operator/` that includes your manifests:
   ```yaml
   apiVersion: kustomize.config.k8s.io/v1beta1
   kind: Kustomization
   
   resources:
     - namespace.yaml
     - tempo-storage-secret.yaml
     - tempostack.yaml  # or tempomonolithic.yaml
   ```

4. Update `configurations/kustomization.yaml` to include the tempo-operator directory:
   ```yaml
   resources:
     - kueue-operator
     - tempo-operator
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
git clone https://github.com/davidebianchi/rhoai-gitops.git
cd rhoai-gitops

# 2. Modify as needed

# 3. Follow the desired tool installation instructions,
#    using the correct branch matching your desired
#    OpenShift AI version (e.g. rhoai-3.0)
```

### Installation with ArgoCD

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
2. **Select the Branch** matching your target OpenShift AI version (e.g., `rhoai-3.0`)
3. **Customize** the configurations for your specific environment
4. **Test** thoroughly in a non-production environment
5. **Maintain** your fork with updates and customizations
6. **Apply** using your GitOps tool (ArgoCD, Flux, etc.) or `kubectl`

## Release Strategy

- **No Formal Releases**: This repository does not have official releases. Users are expected to clone or fork the repository and use it as a basis for their own configurations.
- **Branch per OpenShift AI Version**: Each version of OpenShift AI has a dedicated branch (e.g., `rhoai-3.0`, `rhoai-3.1`) to ensure compatibility.
- **Version Selection**: Always select the branch that corresponds to your target OpenShift AI version.
