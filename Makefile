.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS := -o nounset -o errexit -o pipefail -o noclobber -o hashall -c

kustomize_base_path := pkg
manifests_relative_path := files/usr/local/lib/rancher/k3s/server/manifests/custom
deploy_butane_path := deploy/butane
manifests_custom_base := ${deploy_butane_path}/base/${manifests_relative_path}
manifests_custom_staging := ${deploy_butane_path}/overlays/staging/${manifests_relative_path}
manifests_custom_prod := ${deploy_butane_path}/overlays/prod/${manifests_relative_path}
manifests_custom_rpi4_0 := ${deploy_butane_path}/overlays/rpi4/${manifests_relative_path}

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

kube-manifests-gen-base:
	XTRACE=$${XTRACE:-} hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
													${manifests_custom_base} \
													base

kube-manifests-gen-staging:
	XTRACE=$${XTRACE:-} hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
													${manifests_custom_staging} \
													staging

kube-manifests-gen-rpi4-0:
	XTRACE=$${XTRACE:-} hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
													${manifests_custom_rpi4_0} \
													rpi4-0

kube-manifests-gen-prod: kube-manifests-gen-rpi4-0
	XTRACE=$${XTRACE:-} hack/bin/kube-manifests-gen.sh ${kustomize_base_path} \
													${manifests_custom_prod} \
													prod

kube-manifests-gen-all: clean kube-manifests-gen-base kube-manifests-gen-staging kube-manifests-gen-prod

k3s-tokens-generate-prod:
	hack/bin/k3s-tokens-generate.sh prod-secretsdata.json

deploy_butane_path := deploy/butane
ignition-gen-staging: kube-manifests-gen-staging k3s-tokens-generate
	XTRACE=$${XTRACE:-} hack/bin/ignition-gen-main.sh ${deploy_butane_path}/overlays/staging/main.bu

ignition-gen-rpi4-0: kube-manifests-gen-rpi4-0 k3s-tokens-generate
	XTRACE=$${XTRACE:-} hack/bin/ignition-gen-main.sh ${deploy_butane_path}/overlays/rpi4-0/main.bu

# ignition-gen-base: kube-manifests-gen-base
ignition-gen-base:
	XTRACE=$${XTRACE:-} hack/bin/ignition-gen-main.sh ${deploy_butane_path}/base/main.bu

ignition-gen-prod: kube-manifests-gen-all k3s-tokens-generate-prod
	XTRACE=$${XTRACE:-} VERBOSE=$${VERBOSE:-} \
	hack/bin/ignition-gen-main.sh ${deploy_butane_path}/overlays/prod/main.bu \
								${deploy_butane_path}/overlays/prod/secrets.env

LIB_IGNITION_SERVE := hack/lib/ignition/serve.sh

ignition-serve-gen-certs-base:
	hack/bin/ignition-gen-serving-certs.sh base

# TODO save duplicated extensions as a global Makefile variable
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

ignition-serve-httpd-staging: ignition-gen-staging
	. $(LIB_IGNITION_SERVE)
	hack/bin/httpd-serve.sh $${HTTPD_IMAGE_NAME} staging-main-ign

ignition-serve-nginx-staging: ignition-gen-staging
	. $(LIB_IGNITION_SERVE)
	hack/bin/httpd-serve.sh $${NGINX_IMAGE_NAME} staging-main-ign

ignition-serve-httpd-rpi4-0: ignition-gen-rpi4
	. $(LIB_IGNITION_SERVE)
	hack/bin/httpd-serve.sh $${HTTPD_IMAGE_NAME} rpi4-main-ign

ignition-serve-nginx-rpi4-0: ignition-gen-rpi4
	. $(LIB_IGNITION_SERVE)
	serve $${NGINX_IMAGE_NAME} rpi4-main-ign

ignition-serve-httpd-base: ignition-gen-base
	. $(LIB_IGNITION_SERVE)
	serve $${HTTPD_IMAGE_NAME} base-ignition

ignition-serve-nginx-base: ignition-gen-base
	. $(LIB_IGNITION_SERVE)
	serve $${NGINX_IMAGE_NAME} base-ignition

ignition-serve-httpd-prod: ignition-gen-prod ignition-serve-gen-certs-prod
	serve -s prod-ignition \
		-s prod-ssl-key \
		-s prod-ssl-cert \
		-d $${HTTPD_DROPINS_CONFIG_DEFAULT} \
		-i $${HTTPD_IMAGE_NAME}

# TODO uncomment once completed with testing
# ignition-serve-nginx-prod: ignition-gen-prod ignition-serve-gen-certs-prod
ignition-serve-nginx-prod:
	. $(LIB_IGNITION_SERVE)

	# TODO create a function that returns the podman secret id based on label filter deployment=prod
	serve -s prod-ignition \
		-s ssl-key \
		-s ssl-cert \
		-d $${PWD}/hack/etc/nginx/ignition-secure.conf \
		-d $${PWD}/hack/etc/nginx/default.conf \
		-i $${NGINX_IMAGE_NAME}
