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
	hack/bin/ignition-gen-main.sh -b ${deploy_butane_path}/base/main.bu -s base

ignition-gen-staging: kube-manifests-gen-staging
	hack/bin/ignition-gen-main.sh -b ${deploy_butane_path}/overlays/staging/main.bu -s staging

ignition-gen-rpi4-0: k3s-tokens-generate
	hack/bin/ignition-gen-main.sh -b ${deploy_butane_path}/overlays/rpi4-0/main.bu -s rpi4-0

ignition-gen-prod: kube-manifests-gen-all k3s-tokens-generate-prod
	hack/bin/ignition-gen-main.sh -b ${deploy_butane_path}/overlays/prod/main.bu \
								-e ${deploy_butane_path}/overlays/prod/secrets.env \
								-s prod

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

ignition-serve-base: ignition-gen-base
	. $(LIB_IGNITION_SERVE)
	serve $${NGINX_IMAGE_NAME} ignition-base

ignition-serve-staging: ignition-gen-staging
	. $(LIB_IGNITION_SERVE)
	serve $${NGINX_IMAGE_NAME} ignition-staging

ignition-serve-rpi4-0: ignition-gen-rpi4-0
	. $(LIB_IGNITION_SERVE)
	serve $${NGINX_IMAGE_NAME} ignition-rpi4-0

ignition-serve-prod: ignition-gen-prod ignition-serve-gen-certs-prod
	. $(LIB_IGNITION_SERVE)
	serve -i $${NGINX_IMAGE_NAME} \
		  -d hack/etc/nginx/ignition-secure.conf \
		  -s "prod-ignition,target=$${__nginx_serve_root}/config.ign,mode=0444" \
		  -s "ssl-key-prod,mode=0400,uid=65532,gid=65532" \
		  -s "ssl-cert-prod,mode=0400,uid=65532,gid=65532" \
		  -- \
		  ignition-prod
