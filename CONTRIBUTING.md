# Contributing to OpenDataHub GitOps Repository

Thank you for your interest in contributing to the OpenDataHub GitOps repository! This document provides guidelines and instructions for contributing to this project.

## Table of Contents

- [Contributing to OpenDataHub GitOps Repository](#contributing-to-opendatahub-gitops-repository)
  - [Table of Contents](#table-of-contents)
  - [Getting Started](#getting-started)
    - [Prerequisites](#prerequisites)
  - [Add a New Dependency Operator](#add-a-new-dependency-operator)
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

## Add a New Dependency Operator

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
