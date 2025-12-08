# shellcheck shell=bash

# podman_build_multistage()
podman_build() {
    local -n build_opts="$1"
    local  ctx="$2"

    # TODO add this command to an array, then execute the array string
    # Allows:
    #   * printing the command before running it
    #   * Passing the cmd array on to a function to exec the command (See examples in btrfsmaintenance)
    # shellcheck disable=SC2068
    podman build \
        --format=docker \
        --build-arg-file="$argfile" \
        --build-arg=BUILD_THREADS="$(nproc)" \
        ${build_opts[@]:-} \
        "$ctx"
}

# podman_build_with_options()
#
# Args:
# 1) build_options - string, nameref
#   * Options to be passed to podman build
# 2) image - string, nameref
#   * Name of the image being built
# 3) $3 - string, nameref
#   * Build context directory path
podman_build_with_options() {
    local image="$2"
    local -n context="$3"

    local -r argfile="$context/$ARGFILE_CONF"
    [ -f "$argfile" ] || "$(echo "Build arg file not found: ${argfile}" && exit 1)"

    local -r build_args_env="$BUILD_ENV_BASE/$image.env"
    [ -f "$build_args_env" ] || abort "$build_args_env file not found."
    log "Sourcing $build_args_env"
    # shellcheck source=../../../env/podman/build/example.env
    source "$build_args_env"

    add_build_args "$1" BUILD_ARGS
    add_build_contexts "$1" BUILD_CONTEXTS
    add_build_tag "$1" "$image" LOCAL_REPOSITORY IMAGE_TAGS
    add_container_files "$1" "$context" 

    podman_build "$1" "$context"
}

# add_build_tag()
add_build_tag() {
    local -n opts="$1"
    local img="$2"
    local -n repo="$3"
    local -n tags="$4"

    local -r opt_tag="--tag"
    local -r option_image_tag="$opt_tag=${repo}/${img}:${tags[-1]}"
    log "Adding option: $option_image_tag"
    opts+=("$option_image_tag")
    # podman build is going to create this tag during the image build
    # the remaining tags can be passed to skopeo for copying to the remote repository
    # TODO setup skopeo copy with all additional tags remaining in IMAGE_TAGS
    unset "IMAGE_TAGS[-1]"
}

# add_build_args()
add_build_args() {
    # local -r opt_build_arg="--build-arg"
    local -r opt_build_arg="--build-arg"
    add_build_options "$1" "$2" "$opt_build_arg"
}

# add_build_contexts()
add_build_contexts() {
    # local -r opt_build_context="--build-context"
    local -r opt_build_context="--build-context"
    add_build_options "$1" "$2" "$opt_build_context"
}

add_build_options() {
    # shellcheck disable=SC2178
    local -n opts="$1"
    local -n additional_opts="$2"
    local option="$3"

    # local -r opt_build_context="--build-context"
    local -r opt_build_context="--build-context"
    # shellcheck disable=SC2068
    for new_opt in ${!additional_opts[@]}; do
        new_build_opt="${option}=${new_opt}=${additional_opts["$new_opt"]}"

        log "Adding option: $new_build_opt"
        opts+=("$new_build_opt")
    done
}

# add_container_files()
add_container_files() {
    # shellcheck disable=SC2178
    local -n opts="$1"
    local ctx="$2"

    if [[ ${opts[*]} =~ ('-f'|'--file') ]]; then
        log "User provided Containerfiles found. Skipping addition of container files."
        return
    fi

    log "Adding all containers from $ctx"
    local -r containerfile="Containerfile"
    local -r opt_file="--file"
    mapfile -t -O "${#opts[@]}" "$1" < <(find "$ctx" -iname "$containerfile*" -printf "${opt_file}=%p\n" | sort --sort=version)
}

# build_context_get()
build_context_get() {
    # shellcheck disable=SC2178
    local -n opts="$1"
    local -n ctx="$2"

    ctx="${opts[-1]}"
    [ -d "$ctx" ] || abort "Context directory not found: $ctx"
    unset "opts[-1]"
}

declare -r build_constants="hack/lib/podman/build/constants.env"
[ -f "$build_constants" ] || "$(echo "$build_constants file not found."; exit 1)"
# shellcheck source=constants.env
source "$build_constants"
