.ONESHELL:
SHELL = /bin/bash

deploy-manifests-prod:
	hack/deploy_manifests.sh deploy/butane/base/coreos/files/k3s/manifests

kustomize_base_dir := "pkg"
manifests_prod_dir := "deploy/butane/overlays/prod/usr/local/lib/rancher/k3s/server/manifests"
manifests_base_dir := "deploy/butane/base/usr/local/lib/rancher/k3s/server/manifests"
manifests_staging_dir := "deploy/butane/base/usr/local/lib/rancher/k3s/server/manifests"

clean:
	rm -rf ${manifests_prod_dir}/*
	rm -rf ${manifests_base_dir}/*
	rm -rf ${manifests_staging_dir}/*
	find . -type d -iname "gen_ignition.sh.*" -exec rm -rf {} \;

kube-manifests-gen-base:
	hack/gen_kube_manifests.sh ${kustomize_base_dir} ${manifests_base_dir} base

kube-manifests-gen-prod:
	hack/gen_kube_manifests.sh ${kustomize_base_dir} ${manifests_prod_dir} prod

kube-manifests-gen-staging:
	hack/gen_kube_manifests.sh ${kustomize_base_dir} ${manifests_staging_dir} staging

kube-manifests-gen-rpi4-0:
	hack/gen_kube_manifests.sh ${kustomize_base_dir} ${manifests_prod_dir} rpi4-0

kube-manifests-gen-all: clean kube-manifests-gen-prod kube-manifests-gen-rpi4-0

ignition_dest := "deploy/.ignition"
ignition-gen-staging: kube-manifests-gen-staging
	hack/ignition/gen_ignition.sh deploy/butane/overlays/staging/main.bu ${ignition_dest}/staging_main.ign

ignition-gen-prod: kube-manifests-gen-all
	DEBUG=$${DEBUG:-} hack/ignition/gen_ignition.sh deploy/butane/overlays/prod/main.bu

ignition-gen-rpi4:
	hack/ignition/gen_ignition.sh deploy/butane/overlays/rpi4/main.bu ${ignition_dest}/rpi4_main.ign

ignition-gen-rpi02w-0:
	hack/ignition/gen_ignition.sh deploy/butane/overlays/rpi02w.0/main.bu ${ignition_dest}/rpi02w-0_main.ign

ignition-serve-http-base:
	hack/ignition/deploy/serve_ignition.sh base

ignition-serve-http-staging:
	hack/ignition/deploy/serve_ignition.sh staging

ignition-serve-http-prod: ignition-gen-prod
	hack/ignition/deploy/serve_ignition.sh prod

ignition-serve-http-rpi4:
	hack/ignition/deploy/serve_ignition.sh rpi4

ignition-serve-http-rpi02w-0: ignition-gen-rpi02w-0
	hack/ignition/deploy/serve_ignition.sh rpi02w-0

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

ctr_repo_remote := "docker.io/steve51516"
ctr_repo_local := "localhost/steve51516"
ctr_context_local_dir := "pkg/containers"
ctr_build_env_dir := "hack/env/podman/build"
ctr_build_constant_env_file := "hack/lib/podman/build/constants.env"
ctr_build_script_file := "hack/bin/podman-build.sh"

DEBUG?=
export DEBUG

# TODO setup these targets once their respective context directory Containerfiles have been corrected with the new podman-build.sh expected format
# container-build-archlinuxarm-base:
#    * TODO rework this image build to be much slimmer. It's currently massive.
# container-build-ffmpeg-rpi: container-build-archlinuxarm-base

LIBCAMERA_VERSION_GIT_TAG_OVERRIDE?=
export LIBCAMERA_VERSION_GIT_TAG_OVERRIDE
container-build-libcamera:
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_LIBCAMERA}.env

	[ -v LIBCAMERA_VERSION_GIT_TAG_OVERRIDE ] && echo "LIBCAMERA_VERSION_GIT_TAG_OVERRIDE=$${LIBCAMERA_VERSION_GIT_TAG_OVERRIDE}"
	hack/bin/podman-build.sh ${ctr_context_local_dir}/$${IMAGE_LIBCAMERA}

RPICAM_APPS_VERSION_TAG_OVERRIDE?=
export RPICAM_APPS_VERSION_TAG_OVERRIDE
container-build-rpicam-apps:
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_RPICAM_APPS}.env

	[ -v RPICAM_APPS_VERSION_TAG_OVERRIDE ] && echo "RPICAM_APPS_VERSION_TAG_OVERRIDE=$${RPICAM_APPS_VERSION_TAG_OVERRIDE}"
	hack/bin/podman-build.sh ${ctr_context_local_dir}/$${IMAGE_RPICAM_APPS}

FFMPEG_VERSION_TAG_OVERRIDE?=
export RPICAM_APPS_VERSION_TAG_OVERRIDE
container-build-ffmpeg:
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_FFMPEG}.env

	[ -v FFMPEG_VERSION_TAG_OVERRIDE ] && echo "FFMPEG_VERSION_TAG_OVERRIDE=$${FFMPEG_VERSION_TAG_OVERRIDE}"
	hack/bin/podman-build.sh ${ctr_context_local_dir}/$${IMAGE_FFMPEG}

MOTION_VERSION_OVERRIDE?=
export MOTION_VERSION_OVERRIDE
container-build-motion:
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_MOTION}.env

	[ -v MOTION_VERSION_OVERRIDE ] && echo "MOTION_VERSION_OVERRIDE=$${MOTION_VERSION_OVERRIDE}"
	hack/bin/podman-build.sh ${ctr_context_local_dir}/$${IMAGE_MOTION}

container-build-btrfs-progs:
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_BTRFS_PROGS}.env

	hack/bin/podman-build.sh ${ctr_context_local_dir}/$${IMAGE_BTRFS_PROGS}

### Containerfile End ###
