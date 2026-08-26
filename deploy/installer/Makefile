.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS := -o nounset -o errexit -o pipefail -o hashall -c
-include hack/env/vendor.env

IMAGES := images
DEPLOY_INSTALLER_DIR := deploy/installer
IMAGES_DIR := $(DEPLOY_INSTALLER_DIR)/$(IMAGES)

installer-download-baremetal:
	coreos-installer download \
		--stream stable \
		--platform metal \
		--format iso \
		--directory $(IMAGES_CUSTOMIZED_BASE_DIR)

BASE_NAME := base
STAGING_NAME := staging
PROD_NAME := prod
SECRET_IGNITION_FINAL_BASE_NAME := installer-ignition-$(BASE_NAME)
SECRET_IGNITION_FINAL_STAGING_NAME := installer-ignition-$(STAGING_NAME)
SECRET_IGNITION_FINAL_PROD_NAME := installer-ignition-$(PROD_NAME)

INSTALLER_DIR_BASE := deploy/butane/$(BASE_NAME)/installer
INSTALLER_DIR_STAGING := deploy/butane/overlays/$(STAGING_NAME)/installer
INSTALLER_DIR_PROD := deploy/butane/overlays/$(PROD_NAME)/installer

INSTALL_BUTANE_NAME := install.bu

installer-ignition-gen-base:
	hack/bin/ignition-gen-main.sh -b $(INSTALLER_DIR_BASE)/$(INSTALL_BUTANE_NAME) \
								-n $(SECRET_IGNITION_FINAL_BASE_NAME) \
								-l env=base \
								-l type=installer \
								--

# installer-ignition-gen-staging:
	# hack/bin/ignition-gen-main.sh -b $(INSTALLER_DIR_STAGING)/$(INSTALL_BUTANE_NAME) \
								# -n $(SECRET_IGNITION_FINAL_STAGING_NAME) \
								# -l env=prod \
								# -l type=installer \
								# --

installer-ignition-gen-prod:
	hack/bin/ignition-gen-main.sh -b $(INSTALLER_DIR_PROD)/$(INSTALL_BUTANE_NAME) \
								-n $(SECRET_IGNITION_FINAL_PROD_NAME) \
								-l env=prod \
								-l type=installer \
								--

installer-ignition-gen-all: installer-ignition-gen-base installer-ignition-gen-prod

HACK_LIB_DIR := hack/lib
PODMAN_SECRET_LIB := $(HACK_LIB_DIR)/podman/podman-secret.sh
PODMAN_SECRETS_MOUNT_DIR := var/run/secrets

IMAGES_CUSTOMIZED := $(IMAGES)_customized
IMAGES_CUSTOMIZED_BASE_DIR := $(INSTALLER_DIR_BASE)/$(IMAGES_CUSTOMIZED)
IMAGES_CUSTOMIZED_STAGING_DIR := $(INSTALLER_DIR_STAGING)/$(IMAGES_CUSTOMIZED)
IMAGES_CUSTOMIZED_PROD_DIR := $(INSTALLER_DIR_PROD)/$(IMAGES_CUSTOMIZED)

FILES_LIVE_DIR := files/live
FILES_BASE_LIVE_DIR := $(INSTALLER_DIR_BASE)/$(FILES_LIVE_DIR)
FILES_STAGING_LIVE_DIR := $(INSTALLER_DIR_STAGING)/$(FILES_LIVE_DIR)
FILES_PROD_LIVE_DIR := $(INSTALLER_DIR_PROD)/$(FILES_LIVE_DIR)

# Example of writing this image to a drive:
# Replace this with the correct drive!
# iso_out="/dev/sdc"
# iso_in="coreos-installer/iso/fedora-coreos-43.20251214.3.0-live-iso.x86_64.iso"
# sudo dd if="$iso_in" of="$iso_out" status=progress && sudo sync
installer-iso-customize-base: installer-ignition-gen-base
	iso="$$(find $(IMAGES_DIR) -type f -iname "*.iso" | sort -V | head -n1)"
	iso_out=$(IMAGES_CUSTOMIZED_PROD_DIR)/$$(basename $${iso/.iso/_custom.iso})
	[ -f "$${iso_out}" ] &&  rm $${iso_out}

	hack/vendor/bashkit/local/bin/coreos-installer -s $(SECRET_IGNITION_FINAL_BASE_NAME) \
					-m "type=bind,src=$(FILES_BASE_LIVE_DIR),target=$${__INSTALLER_WORKDIR}/$(FILES_BASE_LIVE_DIR),bind-propagation=rslave,no-dereference,ro=true" \
					-m "type=bind,src=$(IMAGES_DIR),target=$${__INSTALLER_WORKDIR}/$(IMAGES_DIR),bind-propagation=rslave,no-dereference,ro=true" \
					-m "type=bind,src=$(IMAGES_CUSTOMIZED_BASE_DIR),target=$${__INSTALLER_WORKDIR}/$(IMAGES_CUSTOMIZED_BASE_DIR),bind-propagation=rslave,no-dereference" \
					-- \
	 				iso \
					customize \
					--dest-ignition /$(PODMAN_SECRETS_MOUNT_DIR)/$(SECRET_IGNITION_FINAL_BASE_NAME) \
					--output $${iso_out} \
					./$${iso}

installer-iso-customize-prod: installer-ignition-gen-prod
	iso="$$(find $(IMAGES_DIR) -type f -iname "*.iso" | sort -V | head -n1)"
	iso_out=$(IMAGES_CUSTOMIZED_PROD_DIR)/$$(basename $${iso/.iso/_custom.iso})
	[ -f "$${iso_out}" ] &&  rm $${iso_out}

	hack/vendor/bashkit/local/bin/coreos-installer -s $(SECRET_IGNITION_FINAL_PROD_NAME) \
					-m "type=bind,src=$(FILES_PROD_LIVE_DIR),target=$${__INSTALLER_WORKDIR}/$(FILES_PROD_LIVE_DIR),bind-propagation=rslave,no-dereference,ro=true" \
					-m "type=bind,src=$(IMAGES_DIR),target=$${__INSTALLER_WORKDIR}/$(IMAGES_DIR),bind-propagation=rslave,no-dereference,ro=true" \
					-m "type=bind,src=$(IMAGES_CUSTOMIZED_PROD_DIR),target=$${__INSTALLER_WORKDIR}/$(IMAGES_CUSTOMIZED_PROD_DIR),bind-propagation=rslave,no-dereference" \
					-- \
	 				iso \
					customize \
					--network-nmstate $(FILES_PROD_LIVE_DIR)/eno1.nmstate \
					--dest-ignition /$(PODMAN_SECRETS_MOUNT_DIR)/$(SECRET_IGNITION_FINAL_PROD_NAME) \
					--output $${iso_out} \
					./$${iso}

images := "$(HOME)/.local/share/libvirt/images"
installer-download-libvirt:
	coreos-installer download \
					-s ${stream} \
					-p qemu \
					-f qcow2.xz \
					--decompress
					--directory ${IMAGES_DIR}

FCOS_STAGING_NETWORK=fcos-staging
staging-network-build:
	. hack/vendor/bashkit/lib/virsh/virsh-network.sh

	virsh_net_is_defined $(FCOS_STAGING_NETWORK) \
		|| virsh_net_define $(FCOS_STAGING_NETWORK) "Fedora CoreOS Staging Environment Network"

	virsh_net_is_active $(FCOS_STAGING_NETWORK) \
		|| virsh_net_activate $(FCOS_STAGING_NETWORK)

	virsh_net_is_autostart $(FCOS_STAGING_NETWORK) \
		|| virsh_net_autostart $(FCOS_STAGING_NETWORK)

LIBVIRT_ETC_DIR := $(DEPLOY_INSTALLER_DIR)/etc/libvirt
LIBVIRT_ENV_RICK_STAGING := $(LIBVIRT_ETC_DIR)/rick-staging.env

install-staging-vm:
	. $(LIBVIRT_ENV_RICK_STAGING)

	podman secret exists "$${IGNITION_SECRET}" \
		|| { echo "podman secret $${IGNITION_SECRET} does not exist. Generate it first (e.g. 'make ignition-gen-staging' from the repo root)." >&2; exit 1; }

	hack/bin/ensure-staging-vm.sh \
		-l "$${LIBVIRT_DIR}" \
		-n "$${NETWORK_NAME}" \
		-p "$${POOL_NAME}" \
		-d "$${VOLUME_NAME}" \
		-m "$${DOMAIN_NAME}" \
		-s "$${IGNITION_SECRET}"
