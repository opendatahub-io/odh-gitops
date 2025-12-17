# Default target
help: ## Show this help message
	@echo 'Usage: make [target]'
	@echo ''
	@echo 'Available targets:'
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-20s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

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

## Tool Versions
KUSTOMIZE_VERSION ?= v5.8.0
KUBE_LINTER_VERSION ?= v0.7.6
YAMLLINT_VERSION ?= 1.37.1
YQ_VERSION ?= v4.49.2

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"

KUADRANT_NS ?= kuadrant-system # (RHCL operator-related) should match the namespace in Kuadrant CR yaml (default is kuadrant-system)

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
prepare-authorino-tls: yq ## Prepare environment to enable TLS for Authorino by annotating the service, waiting for the TLS certificate secret to be generated, and updating the kustomization.yaml
	@echo "Preparing environment to enable TLS for Authorino..."
	@KUADRANT_NS=$(KUADRANT_NS) K8S_CLI=$(K8S_CLI) PATH="$(LOCALBIN):$$PATH" bash ./scripts/prepare-authorino-tls.sh

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

HELM_TMPL_CMD ?= helm template -f chart/values.yaml -f chart/test/testValues.yaml
HELM_SNAPSHOT_DIR ?= chart/test/snapshots
HELM_DOCS_VERSION ?= 37d3055fece566105cf8cff7c17b7b2355a01677
tmpl_debug ?=

# Internal function to generate and normalize helm output
# Usage: $(call helm-template,output-file,extra-args)
define helm-template
	$(HELM_TMPL_CMD) $(tmpl_debug) --name-template="release-test" -n default $(2) ./chart > $(1)
	@sed -i.bak "s|helm\.sh\/chart\:.*|helm\.sh\/chart\: HELM_CHART_VERSION_REDACTED|" $(1)
	@rm $(1).bak
endef

##@ Helm Chart utilities
.PHONY: chart-snapshots
chart-snapshots: ## Create snapshots for all chart configurations
	@echo "==> Creating default snapshot..."
	$(call helm-template,$(HELM_SNAPSHOT_DIR)/default.snap.yaml,)
	@echo "==> Creating skipCrdCheck snapshot..."
	$(call helm-template,$(HELM_SNAPSHOT_DIR)/skip-crd-check.snap.yaml,--set global.skipCrdCheck=true)
	@echo "==> Snapshots updated!"

.PHONY: chart-test
chart-test: ## Test chart against all snapshots
	@echo "==> Testing default configuration..."
	$(call helm-template,.helm-test-default.yaml,)
	@diff .helm-test-default.yaml $(HELM_SNAPSHOT_DIR)/default.snap.yaml
	@rm .helm-test-default.yaml
	@echo "==> Testing skipCrdCheck configuration..."
	$(call helm-template,.helm-test-skip-crd.yaml,--set global.skipCrdCheck=true)
	@diff .helm-test-skip-crd.yaml $(HELM_SNAPSHOT_DIR)/skip-crd-check.snap.yaml
	@rm .helm-test-skip-crd.yaml
	@echo "==> All tests passed!"

HELM_DOCS = $(shell pwd)/bin/helm-docs
.PHONY: helm-docs-ensure
helm-docs-ensure: ##Download helm-docs locally if necessary.
	$(call go-install-tool,$(HELM_DOCS),github.com/norwoodj/helm-docs/cmd/helm-docs,$(HELM_DOCS_VERSION))

.PHONY: helm-docs
helm-docs: helm-docs-ensure ## Run helm-docs.
	$(HELM_DOCS) --chart-search-root $(shell pwd)/chart -o api-docs.md

.PHONY: helm-verify
helm-verify: ## Verify helm chart installation and DSC components
	NAMESPACE=opendatahub-gitops ./scripts/verify-helm-chart.sh

helm-install-verify: ## Install helm chart and verify installation
	@echo "=== Step 1: Install operators ==="
	helm upgrade --install odh ./chart -n opendatahub-gitops --create-namespace --timeout 1m --set operator.enabled=false
	@echo ""
	@echo "=== Step 2: Wait for CRDs (dependency) ==="
	@./scripts/wait-for-crds.sh
	@echo ""
	@echo "=== Step 3: Install CR and operator (second pass) ==="
	helm upgrade --install odh ./chart -n opendatahub-gitops --timeout 1m --set operator.enabled=true
	@echo ""
	@echo "=== Step 4: Wait for CRDs (operator) ==="
	@bash ./scripts/verify-dependencies.sh
	@bash ./scripts/wait-for-crds.sh --operator
	@echo ""
	@echo "=== Step 5: Install operator CRs ==="
	helm upgrade --install odh ./chart -n opendatahub-gitops --wait --timeout 10m
	@echo ""
	@echo "=== Step 4: Verify installation ==="
	$(MAKE) helm-verify

.PHONY: helm-uninstall
helm-uninstall: ## Uninstall helm chart and all dependencies
	./scripts/uninstall-helm-chart.sh
