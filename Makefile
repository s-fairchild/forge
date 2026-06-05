.ONESHELL:
SHELL = /bin/bash

deploy-manifests-prod:
	hack/deploy_manifests.sh deploy/butane/base/coreos/files/k3s/manifests

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

deploy_butane_path := deploy/butane
ignition-gen-staging: kube-manifests-gen-staging
	XTRACE=$${XTRACE:-} hack/bin/ignition-gen-main.sh ${deploy_butane_path}/overlays/staging/main.bu

ignition-gen-rpi4-0: kube-manifests-gen-rpi4-0
	XTRACE=$${XTRACE:-} hack/bin/ignition-gen-main.sh ${deploy_butane_path}/overlays/rpi4-0/main.bu

# ignition-gen-base: kube-manifests-gen-base
ignition-gen-base:
	XTRACE=$${XTRACE:-} hack/bin/ignition-gen-main.sh ${deploy_butane_path}/base/main.bu

# ignition-gen-prod: kube-manifests-gen-all
ignition-gen-prod:
	XTRACE=$${XTRACE:-} VERBOSE=$${VERBOSE:-} hack/bin/ignition-gen-main.sh \
													${deploy_butane_path}/overlays/prod/main.bu \
													${deploy_butane_path}/overlays/prod/secrets.env

ignition-serve-http-staging: ignition-gen-staging
	XTRACE=$${XTRACE:-} hack/bin/httpd-serve.sh staging-main-ign

ignition-serve-http-rpi4-0: ignition-gen-rpi4
	XTRACE=$${XTRACE:-} hack/bin/httpd-serve.sh rpi4-main-ign

ignition-serve-http-base: ignition-gen-base
	XTRACE=$${XTRACE:-} hack/bin/httpd-serve.sh base-main-ign

ignition-serve-http-prod: ignition-gen-prod
	# TODO progromatically get the volume name to be served the same way ignition-gen-main.sh generates the volume name
	XTRACE=$${XTRACE:-} hack/bin/httpd-serve.sh prod-main-ign

# TODO add --post-install to setup btrfs subvolumes
installer-download-baremetal:
	coreos-installer download \
		--stream stable \
		--platform metal \
		--format iso \
		--directory deploy/coreos-installer/iso

installer-butane-check-base:
	butane --check \
		--strict \
		--files-dir deploy/butane/base/coreos-installer \
			< deploy/butane/base/coreos-installer/install.bu

installer-butane-check-prod: installer-butane-check-base
	butane --check \
		--strict \
		--files-dir deploy/butane \
			< deploy/butane/overlays/prod/coreos-installer/install.bu

installer-ignition-gen-base: installer-butane-check-base
	butane --pretty \
		--strict \
		--files-dir deploy/butane/base/coreos-installer \
			< deploy/butane/base/coreos-installer/install.bu \
			| gzip -v -9 > deploy/butane/base/coreos-installer/install.ign.gz

	. hack/lib/hash.sh
	hash_data=deploy/butane/base/coreos-installer/install.ign.gz
	sha512sum_gen $${hash_data}

installer-ignition-gen-prod: installer-butane-check-prod installer-ignition-gen-base
	. hack/lib/hash.sh
	base_ign_checksum_in=deploy/butane/base/coreos-installer/install.ign.gz.sha512
	sha512sum_check $${base_ign_checksum_in}

	prod_ign_out=deploy/butane/overlays/prod/coreos-installer/install.ign
	prod_butane_in=deploy/butane/overlays/prod/coreos-installer/install.bu
	butane --pretty \
		--strict \
		--files-dir deploy/butane \
		--output $${prod_ign_out} \
			< $${prod_butane_in}
	
	hack/bin/ignition-config-hash-upsert.sh \
		$${base_ign_checksum_in} \
		$${prod_ign_out}

	sha512sum_gen $${prod_ign_out}

installer-ignition-gen-all: installer-ignition-gen-prod

# Example of writing this image to a drive:
# Replace this with the correct drive!
# iso_out="/dev/sdc"
# iso_in="deploy/coreos-installer/iso/fedora-coreos-43.20251214.3.0-live-iso.x86_64.iso"
# sudo dd if="$iso_in" of="$iso_out" status=progress && sudo sync
installer-iso-customize: installer-ignition-gen-prod
	iso="$$(find deploy/coreos-installer/iso -type f -iname "*.iso" | sort -V | head -n1)"

	coreos-installer iso \
				customize \
				--pre-install hack/coreos-installer/post-install.sh \
				-o $${iso/.iso/_custom.iso} \
				./$${iso}

images := "$(HOME)/.local/share/libvirt/images"
installer-download-libvirt:
	coreos-installer download \
				-s ${stream} \
				-p qemu \
				-f qcow2.xz \
				--decompress

staging_vm_name := "rick-dev"
vm-staging-create: ignition-gen-staging
	chcon -t svirt_home_t ${ignition_dest}/staging_main.ign
	hack/manage_dev_vm.sh create ${staging_vm_name} ${ignition_dest}/staging_main.ign

vm-staging-delete:
	hack/manage_dev_vm.sh delete ${staging_vm_name}

vm_ip_address := "192.168.122.2"
ssh_id := ~/.ssh/id_ed25519
# TODO make this configurable to use with production systems
k3s-token-upload:
	hack/upload_k3s_token.sh "rick-dev" \
							 ${ssh_id} \
							 ${vm_ip_address}

### Containerfile Start ###
# TODO convert this into a *simple* reusable shell script
# TODO find and sort by version all Containerfile* to be passed (reference podman-build.sh library)

ctr_repo_remote := "docker.io/steve51516"
ctr_repo_local := "localhost/steve51516"
ctr_build_context := "pkg/containers"
ctr_build_env_dir := "hack/env/podman/build"
ctr_build_constant_env_file := "hack/lib/podman/build/constants.env"
ctr_build_script_file := "hack/bin/podman-build.sh"

# TODO convert these away from using podman-build.sh script and use podman build directly in make targets
# podman-build.sh is proving to be more complicated than it's worth
LIBCAMERA_VERSION_GIT_TAG_OVERRIDE?=
export LIBCAMERA_VERSION_GIT_TAG_OVERRIDE
container-build-libcamera:
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_LIBCAMERA}.env

	[ -v LIBCAMERA_VERSION_GIT_TAG_OVERRIDE ] && echo "LIBCAMERA_VERSION_GIT_TAG_OVERRIDE=$${LIBCAMERA_VERSION_GIT_TAG_OVERRIDE}"
	hack/bin/podman-build.sh ${ctr_build_context}/$${IMAGE_LIBCAMERA}

RPICAM_APPS_VERSION_TAG_OVERRIDE?=
export RPICAM_APPS_VERSION_TAG_OVERRIDE
container-build-rpicam-apps:
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_RPICAM_APPS}.env

	[ -v RPICAM_APPS_VERSION_TAG_OVERRIDE ] && echo "RPICAM_APPS_VERSION_TAG_OVERRIDE=$${RPICAM_APPS_VERSION_TAG_OVERRIDE}"
	hack/bin/podman-build.sh ${ctr_build_context}/$${IMAGE_RPICAM_APPS}

container-build-ffmpeg:
	image_name=ffmpeg
	pushd ${ctr_build_context}/$${image_name} 1> /dev/null
	. <(grep "^FFMPEG_VERSION" argfile.conf)

	podman build \
			--format=docker \
			--platform=linux/amd64 \
			--tag=steve51516/$${image_name}:$${FFMPEG_VERSION} \
			--build-arg-file=argfile.conf \
			--build-arg=BUILD_THREADS=$$(nproc) \
			-f Containerfile-01.base \
			-f Containerfile-02.builder \
			-f Containerfile-03.release \
			.

	popd 1> /dev/null

container-tag-ffmpeg:
	image_name=ffmpeg
	. <(grep "^FFMPEG_VERSION" ${ctr_build_context}/$${image_name}/argfile.conf)

	podman tag \
			localhost/steve51516/$${image_name}:$${FFMPEG_VERSION} \
			localhost/steve51516/$${image_name}:latest

	podman tag \
			localhost/steve51516/$${image_name}:$${FFMPEG_VERSION} \
			docker.io/steve51516/$${image_name}:$${FFMPEG_VERSION}

	podman tag \
			localhost/steve51516/$${image_name}:$${FFMPEG_VERSION} \
			docker.io/steve51516/$${image_name}:latest

container-build-tag-ffmpeg: container-build-ffmpeg container-tag-ffmpeg

container-push-ffmpeg: container-tag-ffmpeg
	image_name=ffmpeg
	. <(grep "^FFMPEG_VERSION" ${ctr_build_context}/$${image_name}/argfile.conf)

	podman image \
			push \
			docker.io/steve51516/$${image_name}:$${FFMPEG_VERSION}

	podman image \
			push \
			docker.io/steve51516/$${image_name}:latest

container-build-push-ffmpeg: container-build-tag-ffmpeg

container-build-motion:
	image_name=motion
	pushd ${ctr_build_context}/$${image_name} 1> /dev/null
	. <(grep "^MOTION_VERSION=" argfile.conf)
	. <(grep "^FFMPEG_VERSION" ../ffmpeg/argfile.conf)

	# TODO add --platform=linux/arm64 once ffmpeg arm build is complete
	podman build \
		--format=docker \
		--platform=linux/amd64 \
		--tag=steve51516/$${image_name}:$${MOTION_VERSION} \
		--build-arg-file=argfile.conf \
		--build-arg=BUILD_THREADS=$$(nproc) \
		--build-arg=FFMPEG_VERSION=$${FFMPEG_VERSION} \
		-f Containerfile-01.base \
		-f Containerfile-02.builder \
		-f Containerfile-03.release \
		.

	popd 1> /dev/null

container-tag-motion:
	image_name=motion
	. <(grep "^MOTION_VERSION=" ${ctr_build_context}/$${image_name}/argfile.conf)

	podman tag \
		localhost/steve51516/$${image_name}:$${MOTION_VERSION} \
		localhost/steve51516/$${image_name}:latest

	podman tag \
		localhost/steve51516/$${image_name}:$${MOTION_VERSION} \
		docker.io/steve51516/$${image_name}:$${MOTION_VERSION}

	podman tag \
		localhost/steve51516/$${image_name}:$${MOTION_VERSION} \
		docker.io/steve51516/$${image_name}:latest

container-push-motion: container-tag-motion
	image_name=motion
	. ${ctr_build_context}/$${image_name}/argfile.conf

	podman image \
		push \
		docker.io/steve51516/$${image_name}:$${MOTION_VERSION}

	podman image \
		push \
		docker.io/steve51516/$${image_name}:latest

container-build-push-motion: container-build-motion container-push-motion

container-build-btrfs-progs:
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_BTRFS_PROGS}.env

	hack/bin/podman-build.sh ${ctr_build_context}/$${IMAGE_BTRFS_PROGS}

container-build-envsubst:
	image_name=envsubst
	pushd ${ctr_build_context}/$${image_name} 1> /dev/null
	. argfile.conf

	podman build \
		--format=docker \
		--platform=linux/amd64 \
		--platform=linux/arm64 \
		--manifest=docker.io/steve51516/envsubst:$${ENVSUBST_VERSION} \
		--build-arg-file=argfile.conf \
		-f Containerfile-01.builder \
		-f Containerfile-02.release \
		.
	
	popd 1> /dev/null
	
	podman tag \
		docker.io/steve51516/$${image_name}:$${ENVSUBST_VERSION} \
		docker.io/steve51516/$${image_name}:latest

container-push-envsubst:
	image_name=envsubst
	. ${ctr_build_context}/$${image_name}/argfile.conf

	podman manifest \
		push \
		docker.io/steve51516/envsubst:$${ENVSUBST_VERSION}

	podman manifest \
		push \
		docker.io/steve51516/envsubst:latest


container-build-push-envsubst: container-build-envsubst container-push-envsubst

### Containerfile End ###

podman-secrets-create-update:
	secret_src_dir="$${PODMAN_SECRET_SOURCE_DIR?'PODMAN_SECRET_SOURCE_DIR must be set.'}"
	. hack/lib/podman/secrets/podman_secrets_create.sh

	podman_secret_create_from_file "$${secret_src_dir}"
