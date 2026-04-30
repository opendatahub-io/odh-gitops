# Default target
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

##@ Version Management

.PHONY: print-rhoai-version
print-rhoai-version: ## Print current RHOAI_VERSION from Makefile
	@echo $(RHOAI_VERSION)

.PHONY: update-rhoai-version
update-rhoai-version: yq ## Update RHOAI_VERSION from ODH-Build-Config
	@./scripts/update-rhoai-version.sh

##@ Tools

## Detect OS and Architecture
OS := $(shell uname -s | tr '[:upper:]' '[:lower:]')
ARCH := $(shell uname -m)

# Map architecture names
ifeq ($(ARCH),x86_64)
	ARCH := amd64
endif
ifeq ($(ARCH),aarch64)
	ARCH := arm64
endif

SED_COMMAND = sed
ifeq ($(OS),darwin)
	SED_COMMAND = gsed
	ifeq (,$(shell which gsed 2>/dev/null))
$(error gsed is required on macOS but was not found. Please install it using: brew install gnu-sed)
	endif
endif

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
PYTHONLOCALBIN ?= $(LOCALBIN)/.python
$(LOCALBIN):
	mkdir -p $(LOCALBIN)
$(PYTHONLOCALBIN):
	mkdir -p $(PYTHONLOCALBIN)
CLEANFILES += $(LOCALBIN)

## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
KUBE_LINTER ?= $(LOCALBIN)/kube-linter
YAMLLINT ?= $(LOCALBIN)/yamllint
K8S_CLI ?= kubectl
YQ ?= $(LOCALBIN)/yq

## Application Versions
# RHOAI version to use for bundle updates - update this when new catalog folder appears in RHOAI-Build-Config
RHOAI_VERSION ?= 3.5.0-ea.1

## Tool Versions
KUSTOMIZE_VERSION ?= v5.8.0
KUBE_LINTER_VERSION ?= v0.7.6
YAMLLINT_VERSION ?= 1.37.1
YQ_VERSION ?= v4.49.2

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"

KUADRANT_NS ?= kuadrant-system # (RHCL operator-related) should match the namespace in Kuadrant CR yaml (default is kuadrant-system)
KUSTOMIZE_MODE ?= true # If false, patches the Authorino CR directly instead of updating the kustomization.yaml

# Operator type for helm installation (odh or rhoai)
OPERATOR_TYPE ?= odh
# Branch to fetch images from Build-Config repo
# example for RHOAI: rhoai-3.4 or rhoai-3.5-ea.1
BUILD_CONFIG_BRANCH ?= main
BUILD_CONFIG_BRANCH := $(strip $(BUILD_CONFIG_BRANCH))

# Applications namespace based on operator type
ifeq ($(OPERATOR_TYPE),rhoai)
	APPLICATIONS_NAMESPACE := redhat-ods-applications
	BUILD_CONFIG_REPO := red-hat-data-services/RHOAI-Build-Config
else
	APPLICATIONS_NAMESPACE := opendatahub
	BUILD_CONFIG_REPO := opendatahub-io/ODH-Build-Config
endif

BUILD_CONFIG_URL := https://raw.githubusercontent.com/$(BUILD_CONFIG_REPO)/$(BUILD_CONFIG_BRANCH)/helm/xks-values-patch.yaml

.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	$(call go-install-tool,$(KUSTOMIZE),sigs.k8s.io/kustomize/kustomize/v5,$(KUSTOMIZE_VERSION))

.PHONY: kube-linter
kube-linter: $(KUBE_LINTER) ## Download kube-linter locally if necessary.
$(KUBE_LINTER): $(LOCALBIN)
	@echo "Downloading kube-linter for $(OS)..."
	@curl -sSL https://github.com/stackrox/kube-linter/releases/download/$(KUBE_LINTER_VERSION)/kube-linter-$(OS).tar.gz | tar xz -C $(LOCALBIN)
	@chmod +x $(KUBE_LINTER)

.PHONY: yamllint
yamllint: $(YAMLLINT) ## Download yamllint locally if necessary.
$(YAMLLINT): $(PYTHONLOCALBIN)
	@echo "Installing yamllint $(YAMLLINT_VERSION) to $(PYTHONLOCALBIN)..."
	@python3 -m pip install --target=$(PYTHONLOCALBIN) --upgrade yamllint==$(YAMLLINT_VERSION) > /dev/null 2>&1
	@echo '#!/bin/bash' > $(YAMLLINT)
	@echo 'PYTHONPATH="$(PYTHONLOCALBIN):$$PYTHONPATH" python3 -m yamllint "$$@"' >> $(YAMLLINT)
	@chmod +x $(YAMLLINT)

.PHONY: yq
yq: $(YQ) ## Download yq locally if necessary.
$(YQ): $(LOCALBIN)
	$(call go-install-tool,$(YQ),github.com/mikefarah/yq/v4,$(YQ_VERSION))

.PHONY: tools
tools: kustomize kube-linter yamllint yq ## Download all validation tools locally.
	@echo ""
	@echo "All validation tools installed in $(LOCALBIN)"

##@ Validation

.PHONY: validate-yaml
validate-yaml: yamllint ## Validate YAML syntax and formatting
	@echo "Validating YAML syntax..."
	@$(YAMLLINT) -c .yamllint.yaml . && echo " YAML validation passed"

.PHONY: validate-kustomize
validate-kustomize: kustomize ## Validate kustomize builds
	@echo "Building all kustomizations..."
	$(call kustomize-build-folder,$(PWD))
	@echo ""
	@echo "All kustomizations built successfully! ✓"

.PHONY: validate-lint
validate-lint: kustomize kube-linter ## Validate best practices with kube-linter
	@echo "Linting Kubernetes manifests..."
	@$(KUSTOMIZE) build . | $(KUBE_LINTER) lint - || echo " Some linting issues found (non-blocking)"
	@echo " Linting completed"

.PHONY: validate-all
validate-all: validate-yaml validate-kustomize validate-lint ## Run all validation checks
	@echo ""
	@echo "=========================================="
	@echo " All validations passed successfully!"
	@echo "=========================================="

.PHONY: apply
apply: kustomize ## Apply kustomize directory as passed as argument
	@echo "Applying kustomization $(FOLDER)..."
	@if [ -z "$(FOLDER)" ]; then \
		echo "Error: FOLDER variable is required. Usage: make apply FOLDER=<path>"; \
		exit 1; \
	fi
	$(KUSTOMIZE) build $(FOLDER) | $(K8S_CLI) apply $(K8S_FLAGS) -f -
	@echo ""
	@echo "Kustomization $(FOLDER) applied successfully! ✓"

.PHONY: apply-and-verify-dependencies
apply-and-verify-dependencies: kustomize ## Apply and verify dependencies
	@$(MAKE) apply FOLDER=dependencies
	@bash ./scripts/verify-dependencies.sh
	@$(MAKE) apply FOLDER=configurations
	@echo "All dependencies and configurations applied successfully! ✓"

.PHONY: remove
remove: kustomize ## Remove kustomize directory as passed as argument
	@echo "Applying kustomization $(FOLDER)..."
	@if [ -z "$(FOLDER)" ]; then \
		echo "Error: FOLDER variable is required. Usage: make apply FOLDER=<path>"; \
		exit 1; \
	fi
	$(KUSTOMIZE) build $(FOLDER) | $(K8S_CLI) delete --ignore-not-found $(K8S_FLAGS) -f -

.PHONY: remove-all-dependencies
remove-all-dependencies:
	@echo "Removing all dependencies..."
	@bash ./scripts/remove-dependencies-pre.sh
	@$(MAKE) remove FOLDER=configurations
	@$(MAKE) remove FOLDER=dependencies
	@bash ./scripts/remove-dependencies-post.sh
	@echo "All dependencies removed successfully! ✓"

.PHONY: prepare-authorino-tls
prepare-authorino-tls: yq ## Prepare environment to enable TLS for Authorino by annotating the service, waiting for the TLS certificate secret to be generated, and patching the Authorino CR.
	@echo "Preparing environment to enable TLS for Authorino..."
	@KUADRANT_NS=$(KUADRANT_NS) K8S_CLI=$(K8S_CLI) KUSTOMIZE_MODE=$(KUSTOMIZE_MODE) bash ./scripts/prepare-authorino-tls.sh

.PHONY: dry-run
dry-run: kustomize ## Dry run kustomize directory as passed as argument
	@$(MAKE) apply FOLDER=$(FOLDER) K8S_FLAGS="--dry-run=client -o yaml"

.PHONY: clean
clean:
	rm -rf $(CLEANFILES)

# go-install-tool will 'go install' any package with custom target and name of binary, if it doesn't exist
# $1 - target path with name of binary (ideally with version)
# $2 - package url which can be installed
# $3 - specific version of package
define go-install-tool
@[ -f "$(1)-$(3)" ] || { \
set -e; \
package=$(2)@$(3) ;\
echo "Downloading $${package}" ;\
rm -f $(1) || true ;\
GOBIN=$(LOCALBIN) go install $${package} ;\
mv $(1) $(1)-$(3) ;\
} ;\
ln -sf $(1)-$(3) $(1)
endef

# kustomize-build-folder will run kustomize build on all kustomization files in a folder
# $1 - folder path to search
# $2 - additional kustomize build flags (optional)
define kustomize-build-folder
@if [ -z "$(1)" ]; then \
	echo "Error: folder path is required"; \
	exit 1; \
fi
@for dir in $$(find $(1) -name "kustomization.yaml" -o -name "kustomization.yml" | xargs -n1 dirname | sort -u); do \
	rel_dir=$${dir#$(1)/}; \
	[ "$$rel_dir" = "$$dir" ] && rel_dir="."; \
	$(KUSTOMIZE) build $$dir > /dev/null && echo "  ✓ $$rel_dir" || (echo "  ✗ $$rel_dir FAILED" && exit 1); \
done
endef

## Helm Chart Configuration
# Charts directory containing all helm charts
CHARTS_DIR ?= charts
# Default chart to operate on (umbrella chart)
CHART_NAME ?=
CHART_PATH ?= $(CHARTS_DIR)/$(if $(CHART_NAME),$(CHART_NAME),rhai-on-openshift-chart)

# Snapshot configuration (in scripts directory)
HELM_DOCS_VERSION ?= 37d3055fece566105cf8cff7c17b7b2355a01677 # v1.14.2
##@ Helm Chart utilities
.PHONY: chart-snapshots
chart-snapshots: yq ## Create snapshots for chart(s). Use CHART_NAME=<name> for specific chart, omit for all
	@./scripts/chart-snapshots.sh --generate $(if $(CHART_NAME),--chart $(CHART_NAME),)

.PHONY: chart-test
chart-test: yq ## Test chart(s) against snapshots. Use CHART_NAME=<name> for specific chart, omit for all
	@./scripts/chart-snapshots.sh --test $(if $(CHART_NAME),--chart $(CHART_NAME),)

HELM_DOCS ?= $(LOCALBIN)/helm-docs
.PHONY: helm-docs-ensure
helm-docs-ensure: $(HELM_DOCS) ## Download helm-docs locally if necessary.
$(HELM_DOCS): $(LOCALBIN)
	$(call go-install-tool,$(HELM_DOCS),github.com/norwoodj/helm-docs/cmd/helm-docs,$(HELM_DOCS_VERSION))

.PHONY: helm-docs
helm-docs: helm-docs-ensure ## Run helm-docs for all charts.
	$(HELM_DOCS) --chart-search-root $(shell pwd)/$(CHARTS_DIR) -o api-docs.md


.PHONY: helm-verify
helm-verify: ## Verify helm chart installation and DSC components
	NAMESPACE=opendatahub-gitops OPERATOR_TYPE=$(OPERATOR_TYPE) ./scripts/verify-helm-chart.sh

# Extra arguments to pass to helm commands (e.g., --set olm.source=custom-catalog)
HELM_EXTRA_ARGS ?=
HELM_INSTALL_VALUES_FILE ?= docs/examples/values-all-components-managed.yaml
# Remove llamastackoperator to avoid nfd and nvidiaGPUOperator dependencies installation on tests.
# TODO: Remove modelsAsService as it depends on PostgreSQL, need to support it in the chart
HELM_INSTALL_ARGS := -f $(HELM_INSTALL_VALUES_FILE) --set components.llamastackoperator.dsc.managementState=Removed --set components.kserve.dsc.modelsAsService.managementState=Removed

.PHONY: helm-install-verify
helm-install-verify: ## Install helm chart and verify installation
	@echo "=== Step 1: Install operators ==="
	helm upgrade --install odh ./$(CHART_PATH) -n opendatahub-gitops --create-namespace $(HELM_INSTALL_ARGS) $(HELM_EXTRA_ARGS)
	@echo "=== Step 2: Wait for CRDs (dependency) ==="
	@./scripts/wait-for-crds.sh
	@bash ./scripts/verify-dependencies.sh
	@echo ""
	@echo "=== Step 3: Enable DSC and DSCInitialization ==="
	helm upgrade --install odh ./$(CHART_PATH) -n opendatahub-gitops $(HELM_INSTALL_ARGS) $(HELM_EXTRA_ARGS)
	@echo ""
	@echo "=== Step 4: Verify operator and DSC installation, reducing dashboard replicas to 1 to reduce resource usage ==="
	@echo "Waiting for odh-dashboard deployment to exist in namespace $(APPLICATIONS_NAMESPACE)..."
	@while ! $(K8S_CLI) get deployment odh-dashboard -n $(APPLICATIONS_NAMESPACE) >/dev/null 2>&1; do echo "Waiting for odh-dashboard deployment..."; sleep 5; done
	$(K8S_CLI) scale deployment odh-dashboard -n $(APPLICATIONS_NAMESPACE) --replicas=1
	$(K8S_CLI) set resources deployment -n $(APPLICATIONS_NAMESPACE) odh-dashboard --containers='*' --requests=cpu=50m,memory=300Mi
	$(K8S_CLI) describe nodes | grep -A 9 "Allocated resources:"
	$(MAKE) helm-verify
	@echo ""
	@echo "=== Step 5: Enable Authorino TLS ==="
	@$(K8S_CLI) delete pod -l app=kuadrant -n kuadrant-system
	@echo ""
	@$(MAKE) prepare-authorino-tls KUSTOMIZE_MODE=false
	@echo ""
	@echo "=== Step 6: Final helm upgrade with wait condition ==="
	helm upgrade --install odh ./$(CHART_PATH) -n opendatahub-gitops --wait --timeout 10m $(HELM_INSTALL_ARGS) $(HELM_EXTRA_ARGS)

## RHAI on XKS Chart
XKS_CHART_PATH ?= $(CHARTS_DIR)/rhai-on-xks-chart
XKS_RELEASE_NAME ?= rhai-on-xks
XKS_NAMESPACE ?= rhai-on-xks
XKS_CLOUD_PROVIDER ?= azure

.PHONY: helm-verify-xks
helm-verify-xks: ## Verify rhai-on-xks-chart installation
	RELEASE_NAME=$(XKS_RELEASE_NAME) NAMESPACE=$(XKS_NAMESPACE) CLOUD_PROVIDER=$(XKS_CLOUD_PROVIDER) ./charts/rhai-on-xks-chart/scripts/verify.sh

.PHONY: helm-install-verify-xks
helm-install-verify-xks: ## Install and verify rhai-on-xks-chart
	@echo "=== Step 1: Install rhai-on-xks-chart ==="
	helm upgrade --install $(XKS_RELEASE_NAME) ./$(XKS_CHART_PATH) -n $(XKS_NAMESPACE) --create-namespace --set $(XKS_CLOUD_PROVIDER).enabled=true $(HELM_EXTRA_ARGS)
	@echo ""
	@echo "=== Step 2: Verify installation ==="
	$(MAKE) helm-verify-xks

.PHONY: helm-uninstall
helm-uninstall: ## Uninstall helm chart and all dependencies
	./scripts/uninstall-helm-chart.sh

.PHONY: update-image
update-image: yq ## Update xks chart images from Build-Config repo into values-$(BUILD_CONFIG_BRANCH).yaml
	@if [ "$(OPERATOR_TYPE)" = "rhoai" ] && [ "$(BUILD_CONFIG_BRANCH)" = "main" ]; then \
		echo "Error: RHOAI requires a release branch (e.g. rhoai-3.4), not 'main'. Set BUILD_CONFIG_BRANCH=<release-branch>." >&2; exit 1; \
	fi; \
	echo "Fetching $(BUILD_CONFIG_URL)..."; \
	patch=$$(mktemp); \
	trap "rm -f $${patch}" EXIT; \
	if ! curl -sfL "$(BUILD_CONFIG_URL)" -o "$${patch}"; then \
		echo "Error: Failed to fetch $(BUILD_CONFIG_URL). Does the branch '$(BUILD_CONFIG_BRANCH)' exist in $(BUILD_CONFIG_REPO)?" >&2; exit 1; \
	fi; \
	override="$(XKS_CHART_PATH)/values-$(BUILD_CONFIG_BRANCH).yaml"; \
	cp "$(XKS_CHART_PATH)/values.yaml" "$${override}" && \
	$(SED_COMMAND) -i '/^  # Example:$$/,/^  #.*value:.*$$/d' "$${override}" && \
	$(YQ) -i '.rhaiOperator.image = load("'"$${patch}"'").rhaiOperator.image' "$${override}" && \
	$(YQ) -i '.rhaiOperator.relatedImages = load("'"$${patch}"'").rhaiOperator.relatedImages' "$${override}" && \
	$(YQ) -i '.hooks.cliImage = load("'"$${patch}"'").hooks.cliImage' "$${override}" && \
	$(YQ) -i '.azure.cloudManager.image = load("'"$${patch}"'").azure.cloudManager.image' "$${override}" && \
	$(YQ) -i '.coreweave.cloudManager.image = load("'"$${patch}"'").coreweave.cloudManager.image' "$${override}" && \
	echo "Created $${override}:" && \
	echo "  rhaiOperator.image: $$($(YQ) '.rhaiOperator.image' "$${override}")" && \
	echo "  relatedImages: $$($(YQ) '.rhaiOperator.relatedImages | length' "$${override}") entries" && \
	echo "  hooks.cliImage: $$($(YQ) '.hooks.cliImage' "$${override}")" && \
	echo "  azure.cloudManager.image: $$($(YQ) '.azure.cloudManager.image' "$${override}")" && \
	echo "  coreweave.cloudManager.image: $$($(YQ) '.coreweave.cloudManager.image' "$${override}")"
