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

## Tool Versions
KUSTOMIZE_VERSION ?= v5.8.0
KUBE_LINTER_VERSION ?= v0.7.6
YAMLLINT_VERSION ?= 1.37.1

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"

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

.PHONY: tools
tools: kustomize kube-linter yamllint ## Download all validation tools locally.
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
	@$(MAKE) remove FOLDER=configurations
	@$(MAKE) remove FOLDER=dependencies
	@bash ./scripts/remove-dependencies.sh
	@echo "All dependencies removed successfully! ✓"

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
