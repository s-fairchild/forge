.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS := -o nounset -o errexit -o pipefail -o noclobber -o hashall -c

deploy_butane_path := deploy/butane
manifests_relative_path := files/usr/local/lib/rancher/k3s/server/manifests/custom
manifests_custom_base := ${deploy_butane_path}/base/${manifests_relative_path}
manifests_custom_staging := ${deploy_butane_path}/overlays/staging/${manifests_relative_path}
manifests_custom_rpi4_0 := ${deploy_butane_path}/overlays/rpi4/${manifests_relative_path}
manifests_custom_prod := ${deploy_butane_path}/overlays/prod/${manifests_relative_path}

clean:
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
kube-manifests-gen-base:
	hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
		${manifests_custom_base} \
		base

kube-manifests-gen-staging:
	hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
		${manifests_custom_staging} \
		staging

kube-manifests-gen-prod:
	hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
		${manifests_custom_prod} \
		prod

kube-manifests-gen-all: clean kube-manifests-gen-base kube-manifests-gen-staging kube-manifests-gen-prod

k3s-tokens-generate-base:
	hack/bin/k3s-tokens-generate.sh -l environment=base -p base

k3s-tokens-generate-staging:
	hack/bin/k3s-tokens-generate.sh -l environment=staging -p staging

k3s-tokens-generate-prod:
	hack/bin/k3s-tokens-generate.sh -l environment=prod -p prod

deploy_butane_path := deploy/butane

ignition-gen-base: kube-manifests-gen-base
	hack/bin/ignition-gen-main.sh \
					-f ${deploy_butane_path}/base/main.bu \
					-p base \
					-l environment=base

ignition-gen-staging: kube-manifests-gen-staging
	hack/bin/ignition-gen-main.sh -f ${deploy_butane_path}/overlays/staging/main.bu \
								  -p staging \
								  -l environment=staging

ignition-gen-rpi4-0: k3s-tokens-generate
	hack/bin/ignition-gen-main.sh -f ${deploy_butane_path}/overlays/rpi4-0/main.bu \
								  -p rpi4-0 \
								  -l environment=rpi4-0

ignition-gen-prod: kube-manifests-gen-all k3s-tokens-generate-prod
	hack/bin/ignition-gen-main.sh -f ${deploy_butane_path}/overlays/prod/main.bu \
								  -p prod \
								  -l environment=prod

ignition-serve-gen-certs-base:
	hack/bin/ignition-gen-serving-certs.sh base \
		-a "DNS:localhost" \
		-a "IP:127.0.0.1"

ignition-serve-gen-certs-staging:
	hack/bin/ignition-gen-serving-certs.sh staging \
		-a "DNS:r10.expresso.lan" \
		-a "DNS:*.r10.expresso.lan"

ignition-serve-gen-certs-rpi4-0:
	hack/bin/ignition-gen-serving-certs.sh rpi4-0 \
		-d 365 \
		-a "DNS:r10.expresso.lan" \
		-a "DNS:*.r10.expresso.lan" \
		-a "IP:10.50.0.202"

ignition-serve-gen-certs-prod:
	hack/bin/ignition-gen-serving-certs.sh prod \
		-d 365 \
		-a "DNS:r10.expresso.lan" \
		-a "DNS:*.r10.expresso.lan" \
		-a "IP:10.50.0.202"

LIB_IGNITION_SERVE := hack/lib/ignition/serve.sh

ignition-serve-base: ignition-gen-base ignition-serve-gen-certs-base k3s-tokens-generate-base
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-base \
		  -k ssl-key-base \
		  -i ignition-base

ignition-serve-staging: ignition-gen-staging ignition-serve-gen-certs-staging k3s-tokens-generate-staging
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-staging \
		  -k ssl-key-staging \
		  -i ignition-staging

# k3s tokens should not be generated for worker node ignition bootstraps
ignition-serve-rpi4-0: ignition-gen-rpi4-0 ignition-serve-gen-certs-rpi4-0
	. $(LIB_IGNITION_SERVE)
	serve -c ssl-cert-rpi4-0 \
		  -k ssl-cert-rpi4-0 \
		  -i ignition-rpi4-0

# ignition-serve-prod: ignition-gen-prod ignition-serve-gen-certs-prod k3s-tokens-generate-prod
ignition-serve-prod:
	. $(LIB_IGNITION_SERVE)
	serve -s var.keyfile.gz \
		  -s appdata.keyfile.gz \
		  -s prod-secrets.json \
		  -s prod-secretsdata.json \
		  -c ssl-cert-prod \
		  -k ssl-key-prod \
		  -i ignition-prod

LIBVIRT_ENV_RICK_STAGING := deploy/installer/etc/libvirt/rick-staging.env

staging-vm-up: ignition-gen-staging
	$(MAKE) -C deploy/installer install-staging-vm

staging-vm-down:
	. $(LIBVIRT_ENV_RICK_STAGING)
	virsh destroy "$${DOMAIN_NAME}"
