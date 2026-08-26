# shellcheck shell=bash

declare -r __podman_build_multi_stage_sourced="true"

# podman_build()
#
# Appends default build options (--format=docker, --build-arg=BUILD_THREADS)
# to the caller-supplied options array, then runs `podman build` with those
# options and the given context directory.
#
# args:
#   * 1) build_opts - nameref; array of podman build options to append to and pass.
#   * 2) ctx_dir    - string; path to the container build context directory.
podman_build() {
    local -n build_opts="$1"
    local ctx_dir="$2"


    info "Appending default podman build options."

    local -r opt_format_docker="--format=docker"
    info "Adding option: $opt_format_docker"
    build_opts+=("$opt_format_docker")

    local -r opt_build_threads="--build-arg=BUILD_THREADS=$(nproc)"
    info "Adding option: $opt_build_threads"
    build_opts+=("$opt_build_threads")

    debug "build_opts=${build_opts[*]}"
    debug "ctx_dir=$ctx_dir"
    info "Starting podman build now."

    # TODO add this command to an array, then execute the array string
    # Allows:
    #   * printing the command before running it
    #   * Passing the cmd array on to a function to exec the command (See examples in btrfsmaintenance)
    # shellcheck disable=SC2068
    podman build \
        ${build_opts[@]:-} \
        "$ctx_dir"
}

# add_build_arg_file()
#
# Appends a --build-arg-file option to the options array when $ARGFILE_CONF
# exists in the build context directory.  Logs a warning and returns without
# modifying the array if the file is absent.
#
# args:
#   * 1) opts - nameref; array of podman build options to append to.
add_build_arg_file() {
    local -n opts="$1"

    local -r build_arg_file_value="$context/$ARGFILE_CONF"
    if [ ! -f "$build_arg_file_value" ]; then
        warn "Build arg file not found: ${build_arg_file_value}. No $ARGFILE_CONF will be added to build options."
        return 0
    fi

    local -r opt_build_arg_file="--build-arg-file"
    local -r build_arg_file="$opt_build_arg_file=$build_arg_file_value"

    info "Adding option: $build_arg_file"
    opts+=("$build_arg_file")
}

# load_podman_build_env()
#
# Sources the per-image .env file and populates build_args_out, build_contexts_out,
# and image_tag_primary_out from the variables it defines (BUILD_ARGS, BUILD_CONTEXTS,
# IMAGE_TAG_PRIMARY / IMAGE_TAG_LATEST).
#
# args:
#   * 1) image               - string; image name used to locate $BUILD_ENV_BASE/$image.env.
#   * 2) build_args_out      - nameref; associative array to receive BUILD_ARGS entries.
#   * 3) build_contexts_out  - nameref; associative array to receive BUILD_CONTEXTS entries.
#   * 4) image_tag_primary_out - nameref; string to receive the primary tag.
load_podman_build_env() {
    local -r image="$1"
    local -n build_args_out="$2"
    local -n build_contexts_out="$3"
    local -n image_tag_primary_out="$4"

    local -r build_env="$BUILD_ENV_BASE/$image.env"
    [ -f "$build_env" ] || fatal --status=5 "$build_env file not found."

    info "Sourcing $build_env"
    # example.env is passed to shellcheck to provide dummy IDE descriptions for referenced variables
    # shellcheck source=../../../env/podman/build/example.env
    . "$build_env"

    if [ -n "${BUILD_ARGS[*]:-}" ]; then
        info "BUILD_ARGS is set in $build_env. Using build-args: ${BUILD_ARGS[*]}"

        # shellcheck disable=SC2068
        for i in ${!BUILD_ARGS[@]}; do
            build_args_out+=(["$i"]="${BUILD_ARGS["$i"]}")
            debug "build_args_out+=([$i]=${BUILD_ARGS[$i]})"
        done
    else
        warn "BUILD_ARGS not set in $build_env. No additional build-args will be used."
    fi

    if [ -n "${BUILD_CONTEXTS[*]:-}" ]; then
        info "BUILD_CONTEXTS is set in $build_env. Keys and values will be added to "

        # shellcheck disable=SC2068
        for i in ${!BUILD_CONTEXTS[@]}; do
            build_contexts_out+=(["$i"]="${BUILD_CONTEXTS["$i"]}")
            debug "build_contexts_out+=[$i]=${BUILD_CONTEXTS[$i]})"
        done
    else
        warn "BUILD_CONTEXTS not set in $build_env. No additional build-contexts will be used."
    fi

    if [ -v IMAGE_TAG_PRIMARY ]; then
        info "IMAGE_TAG_PRIMARY is set in $build_env. The final image built will be tagged: $IMAGE_TAG_PRIMARY"
        image_tag_primary_out="$IMAGE_TAG_PRIMARY"
        debug "image_tag_primary_out=$IMAGE_TAG_PRIMARY"
    else
        warn "IMAGE_TAG_PRIMARY is unset in $build_env. The final image built will be tagged with $IMAGE_TAG_LATEST"
        # shellcheck disable=SC2034
        image_tag_primary_out="$IMAGE_TAG_LATEST"
        debug "image_tag_primary_out=$IMAGE_TAG_LATEST"
    fi

}

# add_build_primary_tag()
#
# Appends a --tag option in the form --tag=<local_repo>/<image>:<tag> to the
# options array.
#
# TODO separate this into its own build.sh library file
#
# args:
#   * 1) opts       - nameref; array of podman build options to append to.
#   * 2) local_repo - string; local container repository prefix.
#   * 3) image      - string; image name.
#   * 4) tag        - string; image tag.
add_build_primary_tag() {
    # shellcheck disable=SC2178
    local -n opts="$1"
    local -r local_repo="$2"
    local -r image="$3"
    local -r tag="$4"

    local -r opt_tag="--tag"
    local -r option_image_tag="$opt_tag=${local_repo}/${image}:${tag}"
    debug "option_image_tag=$option_image_tag"

    info "Adding option: $option_image_tag"
    opts+=("$option_image_tag")
}

# add_build_options()
#
# Iterates over an associative array of key=value pairs and appends
# <option>=<key>=<value> entries to the options array.
#
# TODO separate this into its own build.sh library file
#
# args:
#   * 1) opts            - nameref; array to append to.
#   * 2) additional_opts - nameref; associative array of option key/value pairs.
#   * 3) option          - string; option prefix (e.g. "--build-arg").
add_build_options() {
    # shellcheck disable=SC2178
    local -n opts="$1"
    local -n additional_opts="$2"
    local option="$3"

    # shellcheck disable=SC2068
    for opt_value in ${!additional_opts[@]}; do
        new_build_opt="${option}=${opt_value}=${additional_opts["$opt_value"]}"
        debug "new_build_opt=$new_build_opt"

        info "Adding option: $new_build_opt"
        opts+=("$new_build_opt")
    done
}

# add_build_args()
#
# Convenience wrapper around add_build_options for --build-arg options.
#
# TODO separate this into its own build.sh library file
#
# args:
#   * 1) opts      - nameref; array to append to.
#   * 2) build_args - nameref; associative array of build-arg key/value pairs.
add_build_args() {
    local -r opt_build_arg="--build-arg"
    add_build_options "$1" "$2" "$opt_build_arg"
}

# add_build_additional_contexts()
#
# Convenience wrapper around add_build_options for --build-context options.
#
# TODO separate this into its own build.sh library file
#
# args:
#   * 1) opts           - nameref; array to append to.
#   * 2) build_contexts - nameref; associative array of build-context key/value pairs.
add_build_additional_contexts() {
    local -r opt_build_context="--build-context"
    add_build_options "$1" "$2" "$opt_build_context"
}

# add_container_files_ordered()
#
# Discovers all files matching Containerfile* under the given context directory,
# sorts them by version, and appends --file=<path> options to the options array.
# Skips auto-discovery if the caller already supplied -f or --file options.
#
# args:
#   * 1) opts - nameref; array to append --file options to.
#   * 2) ctx  - string; context directory path to search for Containerfiles.
add_container_files_ordered() {
    # shellcheck disable=SC2178
    local -n opts="$1"
    local ctx="$2"

    if [[ ${opts[*]} =~ ('-f'|'--file') ]]; then
        warn "User provided Containerfiles found. Skipping addition of container files. NO Containerfiles will be added from ${ctx}"
        return 0
    fi

    # TODO Save containerfile list as a variable to log here. Pass this variable to mapfile.
    # info "Building with Containerfiles: "
    info "Gathering Containerfile(s) from context directory: $ctx"
    warn "Container files will be processed in version order."
    local -r containerfile="Containerfile"
    local -r opt_file="--file"
    mapfile -t -O "${#opts[@]}" "$1" < <(find "$ctx" -iname "$containerfile*" -printf "${opt_file}=%p\n" | sort --sort=version)
}

# build_context_get()
#
# Pops the last element of the options array as the build context directory,
# validates that it exists, and assigns it to the ctx nameref.
#
# TODO separate this into its own build.sh library file
#
# args:
#   * 1) opts - nameref; array whose last element is the context directory path.
#   * 2) ctx  - nameref; string that receives the extracted context directory path.
build_context_get() {
    # shellcheck disable=SC2178
    local -n opts="$1"
    local -n ctx="$2"

    ctx="${opts[0]}"
    [ -d "$ctx" ] || fatal "Context directory not found: $ctx"
    unset "opts[-1]"

    info "Container build context directory: ${ctx}"
}

# log_image_tags()
#
# Logs each tag in the provided array at LOG_LEVEL_INFO.
#
# args:
#   * 1) tags - nameref; array of image tag strings to log.
log_image_tags() {
    local -n tags="$1"

    info "The image will be tagged with the following:"
    # shellcheck disable=SC2068
    for t in ${tags[@]}; do
        info "--tag=${t}"
    done
}

# podman_build_with_options()
#
# Orchestrates a full podman build: loads the per-image env file, adds build
# args, build contexts, the primary tag, Containerfiles, and an optional
# build-arg-file, then delegates to podman_build().
#
# args:
#   * 1) build_options - nameref; caller-supplied array of additional podman build options.
#   * 2) image         - string; image name (used to locate the .env file and tag the image).
#   * 3) context       - string; build context directory path.
podman_build_with_options() {
    local -r image="$2"
    local -r context="$3"

    # shellcheck disable=SC2034
    local -A build_args
    # shellcheck disable=SC2034
    local -A build_contexts
    local image_tag_primary
    load_podman_build_env "$image" \
                            build_args \
                            build_contexts \
                            image_tag_primary

    add_build_args "$1" build_args
    add_build_additional_contexts "$1" build_contexts

    add_build_primary_tag "$1" \
                "$LOCAL_REPOSITORY" \
                "$image" \
                "$image_tag_primary"

    add_container_files_ordered "$1" "$context"
    add_build_arg_file "$1"

    podman_build "$1" \
                "$context"
}

if [ "${__bash_logger_adapter_sourced:-}" != "true" ]; then
    declare __bash_logger_adapter_path="hack/vendor/bash-logger-adapter/adapter.sh"
    [ -f "$__bash_logger_adapter_path" ] || { printf '%s\n' "failed to find file: $__bash_logger_adapter_sourced" >&2; exit 1; }
    # shellcheck source=../../../vendor/bash-logger-adapter/adapter.sh
    . "$__bash_logger_adapter_path"
    unset __bash_logger_adapter_path
fi

if [ "${__podman_build_constants_sourced:-}" != "true" ]; then
    declare -r __podman_build_constants_path="hack/lib/podman/build/constants.env"
    [ -f "$__podman_build_constants_path" ] || fatal --status=5 "$__podman_build_constants_path file not found."

    # shellcheck source=constants.env
    . "$__podman_build_constants_path"
fi
