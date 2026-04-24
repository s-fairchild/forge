#!/bin/bash
#
# https://docs.fedoraproject.org/en-US/fedora-coreos/provisioning-raspberry-pi4/#_edk2_separate_firmware_disk_mode
# https://github.com/pftf/RPi4/releases
# https://docs.fedoraproject.org/en-US/fedora-coreos/storage/#_partition_tables

main() {
    # https://github.com/pftf/RPi4/releases/tag/v1.51
    # https://github.com/pftf/RPi4/tree/v1.51
    # version="v1.51"
    version="v1.51"
    # local -r uefi_disk=/dev/sdc1
    local -r uefi_disk=/dev/sdc1
    # local -r uefi_disk_mnt="/tmp/UEFIdisk"
    local -r uefi_disk_mnt="/tmp/UEFIdisk"

    mkfs_vfat "$uefi_disk"
    mount_uefi "$uefi_disk" "$uefi_disk_mnt"
    pushd "$uefi_disk_mnt" || fatal "Failed to pushd into: $uefi_disk_mnt"

    firmware_download_unpack "$version"
    popd

    info "Unmounting $uefi_disk_mnt"
    sudo umount "$uefi_disk_mnt" || error "failed to unmount $uefi_disk_mnt"
}

# firmware_download_unpack()
firmware_download_unpack() {
    local -r version="$1"

    # local -r firmware_release_zip="RPi4_UEFI_Firmware_${version}.zip"
    local -r firmware_release_zip="RPi4_UEFI_Firmware_${version}.zip"

    info "Downloading $firmware_release_zip"
    sudo curl -LO https://github.com/pftf/RPi4/releases/download/${version}/${firmware_release_zip} \
    || fatal "failed to download firmware release version: $version"

    info "Unzipping $firmware_release_zip"
    sudo unzip -n RPi4_UEFI_Firmware_${version}.zip || fatal "failed to unzip $firmware_release_zip"
    sudo rm "$firmware_release_zip" || error "failed to delete $firmware_release_zip"
}

# mount_uefi()
mount_uefi() {
    local -r mnt_part="$1"
    local -r mnt_dir="$2"

    mkdir -p "$mnt_dir" \
    || fatal "failed to create uefi disk mount point directory: $mnt_dir"

    info "Mounting $mnt_part to $mnt_dir"
    sudo mount "$mnt_part" \
                "$mnt_dir" \
    || fatal "failed to mount: $mnt_part mount target: $mnt_dir"
}

# mkfs_vfat()
mkfs_vfat() {
    local -r uefi_part="$1"

    # local -r label="UEFI-SYSTEM"
    local -r label="UEFI-SYSTEM"

    info "Creating vfat EUFI filesystem on device $uefi_part with label $label"
    sudo mkfs.vfat -n "${label}" \
                    "${uefi_part}" \
    || fatal "failed to create vfat filesystem on $uefi_part"

    sudo blkid "$uefi_part"
}

if [ "${__lib_opt_bash_utils_logging_sourced:-}" != "true" ]; then
    # declare -r __lib_opt_bash_utils_logging="hack/lib/opt-bash-utils-logging.sh"
    declare -r __lib_opt_bash_utils_logging="hack/lib/opt-bash-utils-logging.sh"

    [ -f "$__lib_opt_bash_utils_logging" ] || eval "$(echo "$__lib_opt_bash_utils_logging file not found"; exit 5)"
    # shellcheck source=../lib/opt-bash-utils-logging.sh
    . "$__lib_opt_bash_utils_logging"
fi

main
