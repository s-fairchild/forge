.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS := -o nounset -o errexit -o pipefail -o noclobber -o hashall -c

deploy_butane_path := deploy/butane
manifests_relative_path := files/usr/local/lib/rancher/k3s/server/manifests/custom
manifests_custom_base := ${deploy_butane_path}/base/${manifests_relative_path}
manifests_custom_staging := ${deploy_butane_path}/overlays/staging/${manifests_relative_path}
manifests_custom_rpi4_0 := ${deploy_butane_path}/overlays/rpi4/${manifests_relative_path}
manifests_custom_prod := ${deploy_butane_path}/overlays/prod/${manifests_relative_path}

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: help

clean: ## Remove generated kube manifest YAML files from all overlays
	if compgen -G ${manifests_custom_base}/*.yaml > /dev/null; then
		rm -v ${manifests_custom_base}/*.yaml
	fi

	if compgen -G ${manifests_custom_staging}/*.yaml > /dev/null; then
		rm -v ${manifests_custom_staging}/*.yaml
	fi

	if compgen -G ${manifests_custom_prod}/*.yaml > /dev/null; then
		rm -v ${manifests_custom_prod}/*.yaml
	fi

	if compgen -G ${manifests_custom_rpi4_0}/*.yaml > /dev/null; then
		rm -v ${manifests_custom_rpi4_0}/*.yaml
	fi

kustomize_base_path := pkg
generate-kustomize-base: ## Generate kube manifests for the base overlay
	hack/bin/generate-kustomize.sh ${kustomize_base_path} \
		${manifests_custom_base} \
		base

generate-kustomize-staging: ## Generate kube manifests for the staging overlay
	hack/bin/generate-kustomize.sh ${kustomize_base_path} \
		${manifests_custom_staging} \
		staging

generate-kustomize-prod: ## Generate kube manifests for the prod overlay
	hack/bin/generate-kustomize.sh ${kustomize_base_path} \
		${manifests_custom_prod} \
		prod

generate-kustomize: clean generate-kustomize-base generate-kustomize-staging generate-kustomize-prod ## Clean and regenerate kube manifests for all overlays

k3s-tokens-generate-base: ## Generate k3s tokens for the base overlay (skips existing secrets)
	hack/bin/k3s-tokens-generate.sh -l environment=base -p base

k3s-tokens-generate-staging: ## Generate k3s tokens for the staging overlay (skips existing secrets)
	hack/bin/k3s-tokens-generate.sh -l environment=staging -p staging

k3s-tokens-generate-prod: ## Generate k3s tokens for the prod overlay (skips existing secrets)
	hack/bin/k3s-tokens-generate.sh -l environment=prod -p prod

deploy_butane_path := deploy/butane

generate-ignition-base: generate-kustomize-base ## Compile and store the base ignition config as a podman secret
	hack/bin/generate-ignition-main.sh \
					-f ${deploy_butane_path}/base/main.bu \
					-p base \
					-l environment=base

generate-ignition-staging: generate-kustomize-staging ## Compile and store the staging ignition config as a podman secret
	hack/bin/generate-ignition-main.sh -f ${deploy_butane_path}/overlays/staging/main.bu \
								  -p staging \
								  -l environment=staging

generate-ignition-rpi4-0: k3s-tokens-generate ## Compile and store the rpi4-0 ignition config (BROKEN: depends on nonexistent k3s-tokens-generate target)
	hack/bin/generate-ignition-main.sh -f ${deploy_butane_path}/overlays/rpi4-0/main.bu \
								  -p rpi4-0 \
								  -l environment=rpi4-0

generate-ignition-prod: generate-kustomize k3s-tokens-generate-prod ## Compile and store the prod ignition config as a podman secret
	hack/bin/generate-ignition-main.sh -f ${deploy_butane_path}/overlays/prod/main.bu \
								  -p prod \
								  -l environment=prod

generate-ignition: generate-ignition-base generate-ignition-staging generate-ignition-rpi4-0 generate-ignition-prod

generate-serve-certs-base: ## Generate self-signed TLS cert/key secrets for serving base ignition
	hack/bin/generate-serve-certs.sh base \
		-a "DNS:localhost" \
		-a "IP:127.0.0.1"

generate-serve-certs-prod: ## Generate self-signed TLS cert/key secrets for serving prod ignition
	hack/bin/generate-serve-certs.sh prod \
		-d 365 \
		-a "DNS:r10.expresso.lan" \
		-a "DNS:*.r10.expresso.lan" \
		-a "IP:10.50.0.202"

generate-serve-certs: generate-serve-certs-base generate-serve-certs-prod

LIB_IGNITION_SERVE := hack/lib/ignition/serve.sh

ignition-serve-base: generate-ignition-base generate-serve-certs-base k3s-tokens-generate-base ## Serve the base ignition config over HTTPS
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-base \
		  -k ssl-key-base \
		  -i ignition-base

ignition-serve-staging: generate-serve-certs-staging k3s-tokens-generate-staging ## Serve staging's secrets.json/secretsdata.json over HTTPS (ignition itself is delivered via the KubeVirt VM's cloudInitConfigDrive, not HTTP)
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-staging \
		  -k ssl-key-staging \
		  -s staging-secrets.json \
		  -s staging-secretsdata.json

# k3s tokens should not be generated for worker node ignition bootstraps
ignition-serve-rpi4-0: generate-ignition-rpi4-0 generate-serve-certs-rpi4-0 ## Serve the rpi4-0 ignition config over HTTPS
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-rpi4-0 \
		  -k ssl-cert-rpi4-0 \
		  -i ignition-rpi4-0

# ignition-serve-prod: generate-ignition-prod generate-serve-certs-prod k3s-tokens-generate-prod
ignition-serve-prod: ## Serve the prod ignition config over HTTPS (run generate-ignition-prod and generate-serve-certs-prod first)
	. $(LIB_IGNITION_SERVE)
	serve -s var.keyfile.gz \
		  -s appdata.keyfile.gz \
		  -s prod-secrets.json \
		  -s prod-secretsdata.json \
		  -c ssl-cert-prod \
		  -k ssl-key-prod \
		  -i ignition-prod

K3D_CONFIG_DIR := deploy/k3d
# Unimplemented yet
# K3D_CONFIG_BASE := $(K3D_CONFIG_DIR)/base/base.yaml
K3D_CONFIG_STAGING := $(K3D_CONFIG_DIR)/overlays/staging/staging.yaml

PKG_OPERATORS_DIR := pkg/operators
PKG_WORKLOADS_DIR := pkg/workloads

KUBEVIRT_DIR_STAGING := $(PKG_WORKLOADS_DIR)/fcos-vm/overlays/staging
KUBEVIRT_IGNITION_PAYLOAD_STAGING_PODMAN_SECRET_NAME := ignition-staging-kubevirt

k3d-cluster-create-staging: ## Create the staging k3d cluster and install KubeVirt + CDI
	hack/bin/k3d-cluster-manage.sh -f $(K3D_CONFIG_STAGING) -c

k3d-cluster-delete-staging: ## Delete the staging k3d cluster
	hack/bin/k3d-cluster-manage.sh -f $(K3D_CONFIG_STAGING) -d

staging-vm-up: generate-ignition-staging k3d-cluster-create-staging ## Create or update the staging KubeVirt VirtualMachine and its ignition Secret
	hack/bin/kubevirt-vm-manage.sh -c \
		-k $(KUBEVIRT_DIR_STAGING) \
		-i $(KUBEVIRT_IGNITION_PAYLOAD_STAGING_PODMAN_SECRET_NAME)

staging-vm-down: ## Delete the staging KubeVirt VirtualMachine (the k3d cluster keeps running; use k3d-cluster-delete-staging to remove it)
	hack/bin/kubevirt-vm-manage.sh -d -k $(KUBEVIRT_DIR_STAGING)

# Every git submodule under hack/ (bash-logger, bashkit, ...) is independently versioned with
# its own lint tooling; exclude all of them here and lint each via its own skill/toolchain
# instead. Derived from .gitmodules so a future submodule added under hack/ is excluded
# automatically.
lint_hack_exclude_paths := $(shell git config --file .gitmodules --get-regexp path 2> /dev/null \
	| awk '{print $$2}' | grep '^hack/')
lint_hack_find_exclude_args := $(foreach p,${lint_hack_exclude_paths},-not -path '$(p)/*')
lint_hack_jobs := $(shell nproc 2> /dev/null || echo 1)

lint-hack: ## Run shellcheck on all scripts under hack (excludes hack/ submodules), in parallel across nproc jobs
	find hack -name '*.sh' ${lint_hack_find_exclude_args} -print0 \
		| xargs -0 -t -P ${lint_hack_jobs} -n 1 shellcheck

lint-hack-file: ## Run shellcheck on a single file (FILE=path/to/script.sh)
	shellcheck ${FILE}

test_bats_bin := test/vendor/bats-core/bin/bats
test_jobs := $(shell nproc 2> /dev/null || echo 1)
# Only our own test dirs -- NOT `test` itself, which would make --recursive descend into the
# vendored bats-core/bats-support/bats-assert/bats-file/bats-mock submodules' own .bats suites.
# test/bin holds tests for hack/bin/*.sh and test/lib those for hack/lib/**/*.sh. Only the ones
# that exist are passed: bats fails the whole run on a path that doesn't, and git drops an empty
# directory, so test/lib appears once it has a test in it.
test_dirs := $(wildcard test/bin test/lib)

.PHONY: test coverage

test: ## Run the hack/ bats test suite in parallel
	# test_jobs=$$(( $$(nproc || echo -n 3) / 3))
	${test_bats_bin} \
		--jobs ${test_jobs} \
		--no-parallelize-across-files \
		--recursive ${test_dirs} \
		--show-output-of-passing-tests \
		--pretty

coverage: ## Run the hack/ bats test suite under kcov and generate an HTML coverage report
	command -v kcov > /dev/null 2>&1 || { echo "kcov not found; install kcov to run 'make coverage'" >&2; exit 1; }
	rm -rf coverage-report
	kcov --include-path=hack/bin,hack/lib \
		coverage-report \
		${test_bats_bin} \
		--recursive ${test_dirs}

gitleaks-report:
	podman run \
		--rm \
		-v ${PWD}:/repo:O \
		ghcr.io/gitleaks/gitleaks:latest \
			git \
			/repo \
			-v
