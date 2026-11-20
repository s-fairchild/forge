# shellcheck shell=bash
#
# Loads kubevirt-deploy.sh (kubevirt::deploy) and cdi-deploy.sh
# (kubevirt::cdi_deploy).

# shellcheck source=kubevirt-deploy.sh
. "${BASH_SOURCE[0]%/*}/kubevirt-deploy.sh"

# shellcheck source=cdi-deploy.sh
. "${BASH_SOURCE[0]%/*}/cdi-deploy.sh"
