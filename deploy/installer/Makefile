.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS := -o nounset -o errexit -o pipefail -o hashall -c

LIB_BUTANE := hack/lib/ignition/butane.sh
LIB_CHECKSUM := hack/lib/checksum/checksum.sh
LIB_PODMAN_SECRETS := hack/lib/podman/podman-secret.sh

IMAGES_DIR := images
installer-download-baremetal:
	coreos-installer download \
		--stream stable \
		--platform metal \
		--format iso \
		--directory ${IMAGES_DIR}

DEPLOY_BUTANE_DIR := deploy/butane
DEPLOY_BUTANE_BASE_DIR := ${DEPLOY_BUTANE_DIR}/base
INSTALLER_BASE_DIR := ${DEPLOY_BUTANE_BASE_DIR}/installer
INSTALLER_BASE_FILES_DIR := ${INSTALLER_BASE_DIR}/files

INSTALL_BU := install.bu
INSTALL_IGN := install.ign
INSTALL_IGN_GZIP := install.ign.gz

installer-butane-check-base:
	. $(LIB_BUTANE)

	cat $(INSTALLER_BASE_DIR)/$(INSTALL_BU) | butane_check $(INSTALLER_BASE_FILES_DIR)

DEPLOY_BUTANE_OVERLAYS_DIR := $(DEPLOY_BUTANE_DIR)/overlays
INSTALLER_PROD_DIR := $(DEPLOY_BUTANE_OVERLAYS_DIR)/prod/installer
INSTALLER_PROD_FILES_DIR := $(INSTALLER_PROD_DIR)/files

installer-butane-check-prod: installer-butane-check-base
	. $(LIB_BUTANE)

	cat $(INSTALLER_PROD_DIR)/$(INSTALL_BU) | butane_check $(INSTALLER_PROD_FILES_DIR)

installer-ignition-gen-base: installer-butane-check-base
	. $(LIB_CHECKSUM)
	install_ign="$$(butane --strict \
							--files-dir $(INSTALLER_BASE_FILES_DIR) \
							$(INSTALLER_BASE_DIR)/$(INSTALL_BU))"


	. $(LIB_PODMAN_SECRETS)
	podman_secret_create_replace_from_stdin $(INSTALL_IGN)-base <<< $${install_ign}
	podman_secret_create_replace_from_stdin $(INSTALL_IGN).sha512-base \
		<<< "$$(sha512sum_gen <<< $${install_ign} | checksum_format_verification_hash_sha512)"

# TODO update this target to make use of podman secrets created above
installer-ignition-gen-prod:
	# . $(LIB_PODMAN_SECRETS)

	hack/bin/ignition-gen-main.sh deploy/butane/overlays/prod/installer/install.bu

installer-ignition-gen-all: installer-ignition-gen-prod

# Example of writing this image to a drive:
# Replace this with the correct drive!
# iso_out="/dev/sdc"
# iso_in="coreos-installer/iso/fedora-coreos-43.20251214.3.0-live-iso.x86_64.iso"
# sudo dd if="$iso_in" of="$iso_out" status=progress && sudo sync
installer-iso-customize: installer-ignition-gen-prod
	iso="$$(find ${IMAGES_DIR} -type f -iname "*.iso" | sort -V | head -n1)"

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
