.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS := -o nounset -o errexit -o pipefail -o hashall -c
-include hack/env/vendor.env

IMAGES_DIR := deploy/installer/images
installer-download-baremetal:
	coreos-installer download \
		--stream stable \
		--platform metal \
		--format iso \
		--directory ${IMAGES_DIR}

installer-ignition-gen-base:
	hack/bin/ignition-gen-main.sh deploy/butane/base/installer/install.bu

installer-ignition-gen-prod:
	hack/bin/ignition-gen-main.sh deploy/butane/overlays/prod/installer/install.bu

installer-ignition-gen-all: installer-ignition-gen-base installer-ignition-gen-prod

INSTALLER_LIB := hack/lib/ignition/installer.sh
# Example of writing this image to a drive:
# Replace this with the correct drive!
# iso_out="/dev/sdc"
# iso_in="coreos-installer/iso/fedora-coreos-43.20251214.3.0-live-iso.x86_64.iso"
# sudo dd if="$iso_in" of="$iso_out" status=progress && sudo sync
installer-iso-customize-prod: installer-ignition-gen-prod
	iso="$$(find ${IMAGES_DIR} -type f -iname "*.iso" | sort -V | head -n1)"
	. $(INSTALLER_LIB)
	export INSTALLER_SECRET_MOUNTS=("$${secret_id}")
	coreos-installer iso \
		customize \
		-o $${iso/.iso/_custom.iso} \
		./$${iso}

images := "$(HOME)/.local/share/libvirt/images"
installer-download-libvirt:
	coreos-installer download \
					-s ${stream} \
					-p qemu \
					-f qcow2.xz \
					--decompress
					--directory ${IMAGES_DIR}
