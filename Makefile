# VERSION defines the project version for the bundle.
# Update this value when you upgrade the version of your project.
# To re-generate a bundle for another specific version without changing the standard setup, you can:
# - use the VERSION as arg of the bundle target (e.g make bundle VERSION=0.0.2)
# - use environment variables to overwrite this value (e.g export VERSION=0.0.2)
VERSION ?= 2.14.1

# IMAGE_TAG_BASE defines the docker.io namespace and part of the image name for remote images.
# This variable is used to construct full image tags for bundle and catalog images.
#
# For example, running 'make bundle-build bundle-push catalog-build catalog-push' will build and push both
# docker.repository.mark43.io/istio-ratelimit-operator-bundle:$VERSION and docker.repository.mark43.io/istio-ratelimit-operator-catalog:$VERSION.
IMAGE_TAG_BASE ?= docker.repository.mark43.io/istio-ratelimit-operator


# ENVTEST_K8S_VERSION refers to the version of kubebuilder assets to be downloaded by envtest binary.
ENVTEST_K8S_VERSION = 1.29

# Get the currently used golang install path (in GOPATH/bin, unless GOBIN is set)
ifeq (,$(shell go env GOBIN))
GOBIN=$(shell go env GOPATH)/bin
else
GOBIN=$(shell go env GOBIN)
endif

# Setting SHELL to bash allows bash commands to be executed by recipes.
# This is a requirement for 'setup-envtest.sh' in the test target.
# Options are set to exit when a recipe line exits non-zero or a piped command fails.
SHELL = /usr/bin/env bash -o pipefail
.SHELLFLAGS = -ec

.PHONY: all
all: build

##@ General

# The help target prints out all targets with their descriptions organized
# beneath their categories. The categories are represented by '##@' and the
# target descriptions by '##'. The awk commands is responsible for reading the
# entire set of makefiles included in this invocation, looking for lines of the
# file as xyz: ## something, and then pretty-format the target and help. Then,
# if there's a line with ##@ something, that gets pretty-printed as a category.
# More info on the usage of ANSI control characters for terminal formatting:
# https://en.wikipedia.org/wiki/ANSI_escape_code#SGR_parameters
# More info on the awk command:
# http://linuxcommand.org/lc3_adv_awk.php

.PHONY: help
help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z_0-9-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

##@ Development

.PHONY: manifests
manifests: controller-gen ## Generate WebhookConfiguration, ClusterRole and CustomResourceDefinition objects.
	$(CONTROLLER_GEN) rbac:roleName=manager-role crd webhook paths="./..." output:crd:artifacts:config=config/crd/bases

.PHONY: generate
generate: controller-gen ## Generate code containing DeepCopy, DeepCopyInto, and DeepCopyObject method implementations.
	$(CONTROLLER_GEN) object:headerFile="hack/boilerplate.go.txt" paths="./..."

.PHONY: fmt
fmt: ## Run go fmt against code.
	go fmt ./...

.PHONY: vet
vet: ## Run go vet against code.
	go vet ./...

## test: manifests generate fmt vet envtest ## Run tests.
.PHONY: test
test: manifests generate fmt vet ## Run tests.
	KUBEBUILDER_ASSETS="$(shell $(ENVTEST) use $(ENVTEST_K8S_VERSION) --bin-dir $(LOCALBIN) -p path)" go test ./... -coverprofile cover.out

##@ Build

.PHONY: build
build: manifests generate fmt vet ## Build manager binary.
	go build -o bin/manager ./cmd/main.go

.PHONY: run
run: manifests generate fmt vet ## Run a controller from your host.
	go run ./cmd/main.go

.PHONY: docker-build
docker-build: test ## Build docker image with the manager.
	docker build -t ${IMAGE_TAG_BASE} .

.PHONY: docker-push
docker-push: ## Push docker image with the manager.
	docker push ${IMG}

# PLATFORMS defines the target platforms for  the manager image be build to provide support to multiple
# architectures. (i.e. make docker-buildx IMG=myregistry/mypoperator:0.0.1). To use this option you need to:
# - able to use docker buildx . More info: https://docs.docker.com/build/buildx/
# - have enable BuildKit, More info: https://docs.docker.com/develop/develop-images/build_enhancements/
# - be able to push the image for your registry (i.e. if you do not inform a valid value via IMG=<myregistry/image:<tag>> than the export will fail)
# To properly provided solutions that supports more than one platform you should use this option.
PLATFORMS ?= linux/arm64,linux/amd64,linux/s390x,linux/ppc64le
.PHONY: docker-buildx
docker-buildx: test ## Build and push docker image for the manager for cross-platform support
	# copy existing Dockerfile and insert --platform=${BUILDPLATFORM} into Dockerfile.cross, and preserve the original Dockerfile
	sed -e '1 s/\(^FROM\)/FROM --platform=\$$\{BUILDPLATFORM\}/; t' -e ' 1,// s//FROM --platform=\$$\{BUILDPLATFORM\}/' Dockerfile > Dockerfile.cross
	- docker buildx create --name project-v3-builder
	docker buildx use project-v3-builder
	- docker buildx build --push --platform=$(PLATFORMS) --tag ${IMAGE_TAG_BASE}:${VERSION} --tag ${IMAGE_TAG_BASE}:latest -f Dockerfile.cross .
	- docker buildx rm project-v3-builder
	rm Dockerfile.cross



##@ Deployment

ifndef ignore-not-found
  ignore-not-found = false
endif

.PHONY: install
install: manifests kustomize ## Install CRDs into the K8s cluster specified in ~/.kube/config.
	$(KUSTOMIZE) build config/crd | kubectl apply -f -

.PHONY: uninstall
uninstall: manifests kustomize ## Uninstall CRDs from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/crd | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

.PHONY: deploy
deploy: manifests kustomize ## Deploy controller to the K8s cluster specified in ~/.kube/config.
	cd config/manager && $(KUSTOMIZE) edit set image controller=${IMG}
	$(KUSTOMIZE) build config/default | kubectl apply -f -

.PHONY: undeploy
undeploy: ## Undeploy controller from the K8s cluster specified in ~/.kube/config. Call with ignore-not-found=true to ignore resource not found errors during deletion.
	$(KUSTOMIZE) build config/default | kubectl delete --ignore-not-found=$(ignore-not-found) -f -

##@ Build Dependencies

## Location to install dependencies to
LOCALBIN ?= $(shell pwd)/bin
$(LOCALBIN):
	mkdir -p $(LOCALBIN)

## Tool Binaries
KUSTOMIZE ?= $(LOCALBIN)/kustomize
CONTROLLER_GEN ?= $(LOCALBIN)/controller-gen
ENVTEST ?= $(LOCALBIN)/setup-envtest

## Tool Versions
KUSTOMIZE_VERSION ?= v3.8.7
CONTROLLER_TOOLS_VERSION ?= v0.11.3

KUSTOMIZE_INSTALL_SCRIPT ?= "https://raw.githubusercontent.com/kubernetes-sigs/kustomize/master/hack/install_kustomize.sh"
.PHONY: kustomize
kustomize: $(KUSTOMIZE) ## Download kustomize locally if necessary.
$(KUSTOMIZE): $(LOCALBIN)
	test -s $(LOCALBIN)/kustomize || curl -s $(KUSTOMIZE_INSTALL_SCRIPT) | bash -s -- $(subst v,,$(KUSTOMIZE_VERSION)) $(LOCALBIN)

.PHONY: controller-gen
controller-gen: $(CONTROLLER_GEN) ## Download controller-gen locally if necessary.
$(CONTROLLER_GEN): $(LOCALBIN)
	test -s $(LOCALBIN)/controller-gen && $(LOCALBIN)/controller-gen --version | grep -q $(CONTROLLER_TOOLS_VERSION) || \
  GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-tools/cmd/controller-gen@$(CONTROLLER_TOOLS_VERSION)

.PHONY: envtest
envtest: $(ENVTEST) ## Download envtest-setup locally if necessary.
$(ENVTEST): $(LOCALBIN)
	test -s $(LOCALBIN)/setup-envtest || GOBIN=$(LOCALBIN) go install sigs.k8s.io/controller-runtime/tools/setup-envtest@latest


##########################################################
##### Managed by istio-ratelimit-operator CODEOWNERS #####
##########################################################

.PHONY: readme
readme:
	helm-docs -c ./charts/istio-ratelimit-operator -d > README.md
	helm-docs -c ./charts/istio-ratelimit-operator

.PHONY: helm.create.releases
helm.create.releases:
	helm package charts/istio-ratelimit-operator --destination charts/releases
	helm repo index charts/releases

.PHONY: lint
lint:
	go install github.com/golangci/golangci-lint/cmd/golangci-lint@v1.50.1
	golangci-lint run --verbose --timeout 300s

.PHONY: e2e.global.gateway
e2e.global.gateway:
	python3 ./e2e/scripts/main.py --usecases global.gateway

.PHONY: e2e.global.gateway.validate
e2e.global.gateway.validate:
	kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80 &
	sleep 10
	python3 ./e2e/scripts/validate.py --ratelimited --domain podinfo.e2e.dev --path / --gateway

.PHONY: e2e.global.gateway.shadow_mode
e2e.global.gateway.shadow_mode:
	python3 ./e2e/scripts/main.py --usecases global.gateway.shadow_mode

.PHONY: e2e.global.gateway.shadow_mode.validate
e2e.global.gateway.shadow_mode.validate:
	kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80 &
	sleep 10
	python3 ./e2e/scripts/validate.py --domain podinfo.e2e.dev --path / --gateway

.PHONY: e2e.global.gateway.headervaluematch
e2e.global.gateway.headervaluematch:
	python3 ./e2e/scripts/main.py --usecases global.gateway.headervaluematch

.PHONY: e2e.global.gateway.headervaluematch.validate
e2e.global.gateway.headervaluematch.validate:
	kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80 &
	sleep 10
	python3 ./e2e/scripts/validate.py --ratelimited --domain podinfo.e2e.dev --path / --gateway

.PHONY: e2e.global.gateway.headervaluematch.shadow_mode
e2e.global.gateway.headervaluematch.shadow_mode:
	python3 ./e2e/scripts/main.py --usecases global.gateway.headervaluematch.shadow_mode

.PHONY: e2e.global.gateway.headervaluematch.shadow_mode.validate
e2e.global.gateway.headervaluematch.shadow_mode.validate:
	kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80 &
	sleep 10
	python3 ./e2e/scripts/validate.py --domain podinfo.e2e.dev --path / --gateway

.PHONY: e2e.global.sidecar
e2e.global.sidecar:
	python3 ./e2e/scripts/main.py --usecases global.sidecar

.PHONY: e2e.global.sidecar.validate
e2e.global.sidecar.validate:
	python3 ./e2e/scripts/validate.py --ratelimited --domain podinfo.development.svc.cluster.local --path /

.PHONY: e2e.global.sidecar.shadow_mode
e2e.global.sidecar.shadow_mode:
	python3 ./e2e/scripts/main.py --usecases global.sidecar.shadow_mode

.PHONY: e2e.global.sidecar.shadow_mode.validate
e2e.global.sidecar.shadow_mode.validate:
	python3 ./e2e/scripts/validate.py --domain podinfo.development.svc.cluster.local --path /

.PHONY: e2e.global.sidecar.headervaluematch
e2e.global.sidecar.headervaluematch:
	python3 ./e2e/scripts/main.py --usecases global.sidecar.headervaluematch

.PHONY: e2e.global.sidecar.headervaluematch.validate
e2e.global.sidecar.headervaluematch.validate:
	python3 ./e2e/scripts/validate.py --ratelimited --domain podinfo.development.svc.cluster.local --path /

.PHONY: e2e.global.sidecar.headervaluematch.shadow_mode
e2e.global.sidecar.headervaluematch.shadow_mode:
	python3 ./e2e/scripts/main.py --usecases global.sidecar.headervaluematch.shadow_mode

.PHONY: e2e.global.sidecar.headervaluematch.shadow_mode.validate
e2e.global.sidecar.headervaluematch.shadow_mode.validate:
	python3 ./e2e/scripts/validate.py --domain podinfo.development.svc.cluster.local --path /

.PHONY: e2e.local.sidecar
e2e.local.sidecar:
	python3 ./e2e/scripts/main.py --usecases local.sidecar

.PHONY: e2e.local.sidecar.validate
e2e.local.sidecar.validate:
	python3 ./e2e/scripts/validate.py --ratelimited --retry 2 --domain podinfo.development.svc.cluster.local --path /

.PHONY: e2e.local.gateway
e2e.local.gateway:
	python3 ./e2e/scripts/main.py --usecases local.gateway

.PHONY: e2e.local.gateway.validate
e2e.local.gateway.validate:
	kubectl port-forward -n istio-system service/istio-ingressgateway 8080:80 &
	sleep 10
	python3 ./e2e/scripts/validate.py --ratelimited --retry 2 --domain podinfo.e2e.dev --path / --gateway

helm: manifests generate fmt vet
	$(KUSTOMIZE) build config/crd | helmify -crd-dir charts/istio-ratelimit-operator


run-all: helm readme helm.create.releases