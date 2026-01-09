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
	hack/ignition/gen_ignition.sh deploy/butane/overlays/prod/main.bu ${ignition_dest}/prod_main.ign

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

container-build-archlinuxarm-base:
	ctr_image_alarm="archlinuxarm"

	podman build --format=docker -t ${ctr_repo_local}/$${ctr_image_alarm}:arm64 -f pkg/containers/$${ctr_image_alarm}/Containerfile

	podman tag ${ctr_repo_local}/$${ctr_image_alarm}:arm64 ${ctr_repo_remote}/$${ctr_image_alarm}:arm64
	podman tag ${ctr_repo_local}/$${ctr_image_alarm}:arm64 ${ctr_repo_remote}/$${ctr_image_alarm}:latest

container-build-ffmpeg-rpi: container-build-archlinuxarm-base
	ctr_image_ffmpeg_rpi="ffmpeg-rpi"

	podman build --format=docker -t ${ctr_repo_local}/$${ctr_image_ffmpeg_rpi}:arm64 -f pkg/containers/$${ctr_image_ffmpeg_rpi}/Containerfile \
	&& podman tag ${ctr_repo_local}/$${ctr_image_ffmpeg_rpi}:arm64 ${ctr_repo_remote}/$${ctr_image_ffmpeg_rpi}:arm64 \
	&& podman tag ${ctr_repo_local}/$${ctr_image_ffmpeg_rpi}:arm64 ${ctr_repo_remote}/$${ctr_image_ffmpeg_rpi}:latest

container-build-rpicam-apps:
	ctr_image_rpicam_apps="rpicam-apps"
	podman build \
			--format=docker \
			-t ${ctr_repo_local}/$${ctr_image_rpicam_apps}:arm64 \
			-f pkg/containers/$${ctr_image_rpicam_apps}/Containerfile

	podman tag ${ctr_repo_local}/$${ctr_image_rpicam_apps}:arm64 \
				${ctr_repo_remote}/$${ctr_image_rpicam_apps}:arm64

	podman tag ${ctr_repo_local}/$${ctr_image_rpicam_apps}:arm64 \
				${ctr_repo_remote}/$${ctr_image_rpicam_apps}:latest

container-build-motion:
	motion_version_default="4.7.1"
	motion_version="$${MOTION_VERSION:-$${motion_version_default}}"
	ctr_image_motion="motion"

	podman build \
			--format=docker \
			-t ${ctr_repo_local}/$${ctr_image_motion}:v$${motion_version} \
			--build-arg=MOTION_VERSION=$${motion_version} \
			-f pkg/containers/$${ctr_image_motion}/Containerfile

	podman tag ${ctr_repo_local}/$${ctr_image_motion}:v$${motion_version} \
				${ctr_repo_remote}/$${ctr_image_motion}:v$${motion_version}

	podman tag ${ctr_repo_local}/$${ctr_image_motion}:v$${motion_version} \
				${ctr_repo_remote}/$${ctr_image_motion}:latest

### Containerfile End ###
