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
kube-manifests-gen-base: ## Generate kube manifests for the base overlay
	hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
		${manifests_custom_base} \
		base

kube-manifests-gen-staging: ## Generate kube manifests for the staging overlay
	hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
		${manifests_custom_staging} \
		staging

kube-manifests-gen-prod: ## Generate kube manifests for the prod overlay
	hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
		${manifests_custom_prod} \
		prod

kube-manifests-gen-all: clean kube-manifests-gen-base kube-manifests-gen-staging kube-manifests-gen-prod ## Clean and regenerate kube manifests for all overlays

k3s-tokens-generate-base: ## Generate k3s tokens for the base overlay (skips existing secrets)
	hack/bin/k3s-tokens-generate.sh -l environment=base -p base

k3s-tokens-generate-staging: ## Generate k3s tokens for the staging overlay (skips existing secrets)
	hack/bin/k3s-tokens-generate.sh -l environment=staging -p staging

k3s-tokens-generate-prod: ## Generate k3s tokens for the prod overlay (skips existing secrets)
	hack/bin/k3s-tokens-generate.sh -l environment=prod -p prod

deploy_butane_path := deploy/butane

ignition-gen-base: kube-manifests-gen-base ## Compile and store the base ignition config as a podman secret
	hack/bin/ignition-gen-main.sh \
					-f ${deploy_butane_path}/base/main.bu \
					-p base \
					-l environment=base

ignition-gen-staging: kube-manifests-gen-staging ## Compile and store the staging ignition config as a podman secret
	hack/bin/ignition-gen-main.sh -f ${deploy_butane_path}/overlays/staging/main.bu \
								  -p staging \
								  -l environment=staging

ignition-gen-rpi4-0: k3s-tokens-generate ## Compile and store the rpi4-0 ignition config (BROKEN: depends on nonexistent k3s-tokens-generate target)
	hack/bin/ignition-gen-main.sh -f ${deploy_butane_path}/overlays/rpi4-0/main.bu \
								  -p rpi4-0 \
								  -l environment=rpi4-0

ignition-gen-prod: kube-manifests-gen-all k3s-tokens-generate-prod ## Compile and store the prod ignition config as a podman secret
	hack/bin/ignition-gen-main.sh -f ${deploy_butane_path}/overlays/prod/main.bu \
								  -p prod \
								  -l environment=prod

ignition-serve-gen-certs-base: ## Generate self-signed TLS cert/key secrets for serving base ignition
	hack/bin/ignition-gen-serving-certs.sh base \
		-a "DNS:localhost" \
		-a "IP:127.0.0.1"

ignition-serve-gen-certs-staging: ## Generate self-signed TLS cert/key secrets for serving staging ignition
	hack/bin/ignition-gen-serving-certs.sh staging \
		-a "DNS:r10.expresso.lan" \
		-a "DNS:*.r10.expresso.lan"

ignition-serve-gen-certs-rpi4-0: ## Generate self-signed TLS cert/key secrets for serving rpi4-0 ignition
	hack/bin/ignition-gen-serving-certs.sh rpi4-0 \
		-d 365 \
		-a "DNS:r10.expresso.lan" \
		-a "DNS:*.r10.expresso.lan" \
		-a "IP:10.50.0.202"

ignition-serve-gen-certs-prod: ## Generate self-signed TLS cert/key secrets for serving prod ignition
	hack/bin/ignition-gen-serving-certs.sh prod \
		-d 365 \
		-a "DNS:r10.expresso.lan" \
		-a "DNS:*.r10.expresso.lan" \
		-a "IP:10.50.0.202"

LIB_IGNITION_SERVE := hack/lib/ignition/serve.sh

ignition-serve-base: ignition-gen-base ignition-serve-gen-certs-base k3s-tokens-generate-base ## Serve the base ignition config over HTTPS
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-base \
		  -k ssl-key-base \
		  -i ignition-base

ignition-serve-staging: ignition-gen-staging ignition-serve-gen-certs-staging k3s-tokens-generate-staging ## Serve the staging ignition config over HTTPS
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-staging \
		  -k ssl-key-staging \
		  -i ignition-staging

# k3s tokens should not be generated for worker node ignition bootstraps
ignition-serve-rpi4-0: ignition-gen-rpi4-0 ignition-serve-gen-certs-rpi4-0 ## Serve the rpi4-0 ignition config over HTTPS
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-rpi4-0 \
		  -k ssl-cert-rpi4-0 \
		  -i ignition-rpi4-0

# ignition-serve-prod: ignition-gen-prod ignition-serve-gen-certs-prod k3s-tokens-generate-prod
ignition-serve-prod: ## Serve the prod ignition config over HTTPS (run ignition-gen-prod and ignition-serve-gen-certs-prod first)
	. $(LIB_IGNITION_SERVE)
	serve -s var.keyfile.gz \
		  -s appdata.keyfile.gz \
		  -s prod-secrets.json \
		  -s prod-secretsdata.json \
		  -c ssl-cert-prod \
		  -k ssl-key-prod \
		  -i ignition-prod

LIBVIRT_ENV_RICK_STAGING := deploy/installer/etc/libvirt/rick-staging.env

staging-vm-up: ignition-gen-staging ## Bring up the rick-staging libvirt VM (transient domain)
	$(MAKE) -C deploy/installer install-staging-vm

staging-vm-down: ## Tear down the rick-staging libvirt VM
	. $(LIBVIRT_ENV_RICK_STAGING)
	virsh destroy "$${DOMAIN_NAME}"

# hack/vendor/bash-logger is an independently-versioned submodule with its own lint tooling;
# exclude it here and lint it via that submodule's own skill/toolchain instead.
lint_hack_exclude_path := hack/vendor/bash-logger

lint-hack: ## Run shellcheck on all scripts under hack (excludes bash-logger submodule)
	find hack -name '*.sh' -not -path '${lint_hack_exclude_path}/*' -exec shellcheck {} +

lint-hack-file: ## Run shellcheck on a single file (FILE=path/to/script.sh)
	shellcheck ${FILE}
