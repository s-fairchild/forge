.ONESHELL:
SHELL = /bin/bash
.SHELLFLAGS := -o nounset -o errexit -o pipefail -o hashall -c

DEPLOY_INSTALLER_DIR := deploy/installer
TITAN_LOCAL_SHARE_DIR := $(HOME)/.local/share/titan/installer
IMAGES_DIR := $(TITAN_LOCAL_SHARE_DIR)/images
STREAM := stable

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: help

installer-download-baremetal: ## Download the FCOS bare-metal ISO into IMAGES_CUSTOMIZED_BASE_DIR
	mkdir -p $(IMAGES_CUSTOMIZED_BASE_DIR)

	hack/vendor/bashkit/local/bin/coreos-installer \
		-m type=bind,src=$(PWD)/$(DEPLOY_INSTALLER_DIR),target=$(PWD)/$(DEPLOY_INSTALLER_DIR) \
		-- \
		download \
		--stream $(STREAM) \
		--platform metal \
		--format iso \
		--directory $(IMAGES_CUSTOMIZED_BASE_DIR)

installer-download-libvirt: ## Download the FCOS qemu qcow2.xz image into ~/.local/share/libvirt/images
	libvirt_images_dir=$(HOME)/.local/share/libvirt/images
	mkdir -p $${libvirt_images_dir}
	chcon -t svirt_home_t $${libvirt_images_dir}

	hack/vendor/bashkit/local/bin/coreos-installer \
		-m type=bind,src=$${libvirt_images_dir},target=$${libvirt_images_dir} \
		-- \
		download \
		-s $(STREAM) \
		-p qemu \
		-f qcow2.xz \
		-d \
		-C $${libvirt_images_dir}

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

# There is no installer-ignition-gen-staging target as it's not needed
# The qemu base disk image is mounted and ignition is applied this way

installer-ignition-gen-base: ## Compile the base installer ignition config (STALE: -b/-n flags no longer match ignition-gen-main.sh's -f/-p getopts)
	hack/bin/ignition-gen-main.sh -b $(INSTALLER_DIR_BASE)/$(INSTALL_BUTANE_NAME) \
								-n $(SECRET_IGNITION_FINAL_BASE_NAME) \
								-l env=base \
								-l type=installer \
								--

installer-ignition-gen-prod: ## Compile the prod installer ignition config (STALE: -b/-n flags no longer match ignition-gen-main.sh's -f/-p getopts)
	hack/bin/ignition-gen-main.sh -b $(INSTALLER_DIR_PROD)/$(INSTALL_BUTANE_NAME) \
								-n $(SECRET_IGNITION_FINAL_PROD_NAME) \
								-l env=prod \
								-l type=installer \
								--

installer-ignition-gen-all: installer-ignition-gen-base installer-ignition-gen-prod ## Compile the base and prod installer ignition configs

HACK_LIB_DIR := hack/lib
INSTALLER_LIB := $(HACK_LIB_DIR)/ignition/installer.sh
PODMAN_SECRET_LIB := $(HACK_LIB_DIR)/podman/podman-secret.sh
PODMAN_SECRETS_MOUNT_DIR := var/run/secrets

IMAGES_CUSTOMIZED_BASE_DIR := $(TITAN_LOCAL_SHARE_DIR)/images_customized/base
IMAGES_CUSTOMIZED_STAGING_DIR := $(TITAN_LOCAL_SHARE_DIR)/images_customized/staging
IMAGES_CUSTOMIZED_PROD_DIR := $(TITAN_LOCAL_SHARE_DIR)/images_customized/prod

FILES_LIVE_DIR := files/live
FILES_BASE_LIVE_DIR := $(INSTALLER_DIR_BASE)/$(FILES_LIVE_DIR)
FILES_STAGING_LIVE_DIR := $(INSTALLER_DIR_STAGING)/$(FILES_LIVE_DIR)
FILES_PROD_LIVE_DIR := $(INSTALLER_DIR_PROD)/$(FILES_LIVE_DIR)

# Example of writing this image to a drive:
# Replace this with the correct drive!
# iso_out="/dev/sdc"
# iso_in="coreos-installer/iso/fedora-coreos-43.20251214.3.0-live-iso.x86_64.iso"
# sudo dd if="$iso_in" of="$iso_out" status=progress && sudo sync
installer-iso-customize-base: installer-ignition-gen-base ## Embed base ignition into the newest ISO under IMAGES_DIR via coreos-installer
	mkdir -p $(IMAGES_DIR) $(IMAGES_CUSTOMIZED_BASE_DIR)
	iso="$$(find $(IMAGES_DIR) -type f -iname "*.iso" | sort -V | head -n1)"
	iso_out=$(IMAGES_CUSTOMIZED_PROD_DIR)/$$(basename $${iso/.iso/_custom.iso})
	[ -f "$${iso_out}" ] &&  rm $${iso_out}

	. $(INSTALLER_LIB)
	coreos-installer -s $(SECRET_IGNITION_FINAL_BASE_NAME) \
					-m "type=bind,src=$(FILES_BASE_LIVE_DIR),target=$${__INSTALLER_WORKDIR}/$(FILES_BASE_LIVE_DIR),bind-propagation=rslave,no-dereference,ro=true" \
					-m "type=bind,src=$(IMAGES_DIR),target=$${__INSTALLER_WORKDIR}/$(IMAGES_DIR),bind-propagation=rslave,no-dereference,ro=true" \
					-m "type=bind,src=$(IMAGES_CUSTOMIZED_BASE_DIR),target=$${__INSTALLER_WORKDIR}/$(IMAGES_CUSTOMIZED_BASE_DIR),bind-propagation=rslave,no-dereference" \
					-- \
	 				iso \
					customize \
					--dest-ignition /$(PODMAN_SECRETS_MOUNT_DIR)/$(SECRET_IGNITION_FINAL_BASE_NAME) \
					--output $${iso_out} \
					$${iso}

installer-iso-customize-prod: installer-ignition-gen-prod ## Embed prod ignition into the newest ISO under IMAGES_DIR via coreos-installer
	mkdir -p $(IMAGES_DIR) $(IMAGES_CUSTOMIZED_PROD_DIR)
	iso="$$(find $(IMAGES_DIR) -type f -iname "*.iso" | sort -V | head -n1)"
	iso_out=$(IMAGES_CUSTOMIZED_PROD_DIR)/$$(basename $${iso/.iso/_custom.iso})
	[ -f "$${iso_out}" ] &&  rm $${iso_out}

	. $(INSTALLER_LIB)
	coreos-installer -s $(SECRET_IGNITION_FINAL_PROD_NAME) \
					 -m "type=bind,src=$(FILES_PROD_LIVE_DIR),target=$${__INSTALLER_WORKDIR}/$(FILES_PROD_LIVE_DIR),bind-propagation=rslave,no-dereference,ro=true" \
					 -m "type=bind,src=$(IMAGES_DIR),target=$${__INSTALLER_WORKDIR}/$(IMAGES_DIR),bind-propagation=rslave,no-dereference,ro=true" \
					 -m "type=bind,src=$(IMAGES_CUSTOMIZED_PROD_DIR),target=$${__INSTALLER_WORKDIR}/$(IMAGES_CUSTOMIZED_PROD_DIR),bind-propagation=rslave,no-dereference" \
					 -- \
	 				 iso \
					 customize \
					 --network-nmstate $(FILES_PROD_LIVE_DIR)/eno1.nmstate \
					 --dest-ignition /$(PODMAN_SECRETS_MOUNT_DIR)/$(SECRET_IGNITION_FINAL_PROD_NAME) \
					 --output $${iso_out} \
					 $${iso}

FCOS_STAGING_NETWORK=fcos-staging
staging-network-build: ## Define/activate/autostart the fcos-staging libvirt network (STALE path: missing local/ segment)
	. hack/vendor/bashkit/lib/virsh/virsh-network.sh

	if ! virsh_net_is_defined $(FCOS_STAGING_NETWORK); then
		virsh_net_define $(FCOS_STAGING_NETWORK) "Fedora CoreOS Staging Environment Network"
	fi
	
	if ! virsh_net_is_active $(FCOS_STAGING_NETWORK); then
		virsh_net_activate $(FCOS_STAGING_NETWORK)
	fi
	
	if ! virsh_net_is_autostart $(FCOS_STAGING_NETWORK); then
		virsh_net_autostart $(FCOS_STAGING_NETWORK)
	fi

LIBVIRT_ENV_RICK_STAGING := $(DEPLOY_INSTALLER_DIR)/etc/libvirt/rick-staging.env

install-staging-vm: ## Idempotently define and create the rick-staging libvirt VM from an ignition podman secret
	# hack/bin/ensure-staging-vm.sh (like every non-bashkit consumer) sources its
	# dependencies relative to the repo root, and LIBVIRT_DIR in the env file below
	# is itself a repo-root-relative path -- so this recipe must run from there,
	# regardless of whether it was reached via `make -C deploy/installer ...`.
	cd "$$(git rev-parse --show-toplevel)"

	. $(LIBVIRT_ENV_RICK_STAGING)

	if ! podman secret exists "$${IGNITION_SECRET}"; then
		echo "podman secret $${IGNITION_SECRET} does not exist. Generate it first (e.g. 'make ignition-gen-staging' from the repo root)." >&2
		exit 1
	fi

	hack/bin/ensure-staging-vm.sh \
		-l "$${LIBVIRT_DIR}" \
		-p "$${POOL_NAME}" \
		-d "$${VOLUME_NAME}" \
		-m "$${DOMAIN_NAME}" \
		-s "$${IGNITION_SECRET}"
