# TODO convert this into a *simple* reusable shell script
# TODO find and sort by version all Containerfile* to be passed (reference podman-build.sh library)

ctr_repo_remote := "docker.io/steve51516"
ctr_repo_local := "localhost/steve51516"
ctr_build_context := "pkg/containers"
ctr_build_env_dir := "hack/env/podman/build"
ctr_build_constant_env_file := "hack/lib/podman/build/constants.env"
ctr_build_script_file := "hack/bin/podman-build.sh"

help: ## Show this help message
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z0-9_-]+:.*##/ { printf "  \033[36m%-32s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

.PHONY: help

# TODO convert these away from using podman-build.sh script and use podman build directly in make targets
# podman-build.sh is proving to be more complicated than it's worth
LIBCAMERA_VERSION_GIT_TAG_OVERRIDE?=
export LIBCAMERA_VERSION_GIT_TAG_OVERRIDE
container-build-libcamera: ## Build the libcamera image via podman-build.sh (LIBCAMERA_VERSION_GIT_TAG_OVERRIDE optional)
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_LIBCAMERA}.env

	[ -v LIBCAMERA_VERSION_GIT_TAG_OVERRIDE ] && echo "LIBCAMERA_VERSION_GIT_TAG_OVERRIDE=$${LIBCAMERA_VERSION_GIT_TAG_OVERRIDE}"
	hack/bin/podman-build.sh ${ctr_build_context}/$${IMAGE_LIBCAMERA}

RPICAM_APPS_VERSION_TAG_OVERRIDE?=
export RPICAM_APPS_VERSION_TAG_OVERRIDE
container-build-rpicam-apps: ## Build the rpicam-apps image via podman-build.sh (RPICAM_APPS_VERSION_TAG_OVERRIDE optional)
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_RPICAM_APPS}.env

	[ -v RPICAM_APPS_VERSION_TAG_OVERRIDE ] && echo "RPICAM_APPS_VERSION_TAG_OVERRIDE=$${RPICAM_APPS_VERSION_TAG_OVERRIDE}"
	hack/bin/podman-build.sh ${ctr_build_context}/$${IMAGE_RPICAM_APPS}

container-build-ffmpeg: ## Build the ffmpeg image tagged with its argfile.conf FFMPEG_VERSION
	image_name=ffmpeg
	pushd ${ctr_build_context}/$${image_name} 1> /dev/null
	. <(grep "^FFMPEG_VERSION" argfile.conf)

	podman build \
			--format=docker \
			--platform=linux/amd64 \
			--tag=steve51516/$${image_name}:$${FFMPEG_VERSION} \
			--build-arg-file=argfile.conf \
			--build-arg=BUILD_THREADS=$$(nproc) \
			-f Containerfile-01.base \
			-f Containerfile-02.builder \
			-f Containerfile-03.release \
			.

	popd 1> /dev/null

container-tag-ffmpeg: ## Tag the built ffmpeg image as :latest and docker.io/steve51516
	image_name=ffmpeg
	. <(grep "^FFMPEG_VERSION" ${ctr_build_context}/$${image_name}/argfile.conf)

	podman tag \
			localhost/steve51516/$${image_name}:$${FFMPEG_VERSION} \
			localhost/steve51516/$${image_name}:latest

	podman tag \
			localhost/steve51516/$${image_name}:$${FFMPEG_VERSION} \
			docker.io/steve51516/$${image_name}:$${FFMPEG_VERSION}

	podman tag \
			localhost/steve51516/$${image_name}:$${FFMPEG_VERSION} \
			docker.io/steve51516/$${image_name}:latest

container-build-tag-ffmpeg: container-build-ffmpeg container-tag-ffmpeg ## Build and tag the ffmpeg image

container-push-ffmpeg: container-tag-ffmpeg ## Push the tagged ffmpeg image to docker.io/steve51516
	image_name=ffmpeg
	. <(grep "^FFMPEG_VERSION" ${ctr_build_context}/$${image_name}/argfile.conf)

	podman image \
			push \
			docker.io/steve51516/$${image_name}:$${FFMPEG_VERSION}

	podman image \
			push \
			docker.io/steve51516/$${image_name}:latest

container-build-push-ffmpeg: container-build-tag-ffmpeg ## Build, tag, and push the ffmpeg image (NOTE: missing container-push-ffmpeg dependency)

container-build-motion: ## Build the motion image tagged with its argfile.conf MOTION_VERSION
	image_name=motion
	pushd ${ctr_build_context}/$${image_name} 1> /dev/null
	. <(grep "^MOTION_VERSION=" argfile.conf)
	. <(grep "^FFMPEG_VERSION" ../ffmpeg/argfile.conf)

	# TODO add --platform=linux/arm64 once ffmpeg arm build is complete
	podman build \
		--format=docker \
		--platform=linux/amd64 \
		--tag=steve51516/$${image_name}:$${MOTION_VERSION} \
		--build-arg-file=argfile.conf \
		--build-arg=BUILD_THREADS=$$(nproc) \
		--build-arg=FFMPEG_VERSION=$${FFMPEG_VERSION} \
		-f Containerfile-01.base \
		-f Containerfile-02.builder \
		-f Containerfile-03.release \
		.

	popd 1> /dev/null

container-tag-motion: ## Tag the built motion image as :latest and docker.io/steve51516
	image_name=motion
	. <(grep "^MOTION_VERSION=" ${ctr_build_context}/$${image_name}/argfile.conf)

	podman tag \
		localhost/steve51516/$${image_name}:$${MOTION_VERSION} \
		localhost/steve51516/$${image_name}:latest

	podman tag \
		localhost/steve51516/$${image_name}:$${MOTION_VERSION} \
		docker.io/steve51516/$${image_name}:$${MOTION_VERSION}

	podman tag \
		localhost/steve51516/$${image_name}:$${MOTION_VERSION} \
		docker.io/steve51516/$${image_name}:latest

container-push-motion: container-tag-motion ## Push the tagged motion image to docker.io/steve51516
	image_name=motion
	. ${ctr_build_context}/$${image_name}/argfile.conf

	podman image \
		push \
		docker.io/steve51516/$${image_name}:$${MOTION_VERSION}

	podman image \
		push \
		docker.io/steve51516/$${image_name}:latest

container-build-push-motion: container-build-motion container-push-motion ## Build, tag, and push the motion image

container-build-btrfs-progs: ## Build the btrfs-progs image via podman-build.sh
	. ${ctr_build_constant_env_file}
	. ${ctr_build_env_dir}/$${IMAGE_BTRFS_PROGS}.env

	hack/bin/podman-build.sh ${ctr_build_context}/$${IMAGE_BTRFS_PROGS}

container-build-envsubst: ## Build a multi-arch (amd64/arm64) envsubst manifest tagged with its argfile.conf ENVSUBST_VERSION
	image_name=envsubst
	pushd ${ctr_build_context}/$${image_name} 1> /dev/null
	. argfile.conf

	podman build \
		--format=docker \
		--platform=linux/amd64 \
		--platform=linux/arm64 \
		--manifest=docker.io/steve51516/envsubst:$${ENVSUBST_VERSION} \
		--build-arg-file=argfile.conf \
		-f Containerfile-01.builder \
		-f Containerfile-02.release \
		.
	
	popd 1> /dev/null
	
	podman tag \
		docker.io/steve51516/$${image_name}:$${ENVSUBST_VERSION} \
		docker.io/steve51516/$${image_name}:latest

container-push-envsubst: ## Push the envsubst manifest to docker.io/steve51516
	image_name=envsubst
	. ${ctr_build_context}/$${image_name}/argfile.conf

	podman manifest \
		push \
		docker.io/steve51516/envsubst:$${ENVSUBST_VERSION}

	podman manifest \
		push \
		docker.io/steve51516/envsubst:latest


container-build-push-envsubst: container-build-envsubst container-push-envsubst ## Build and push the envsubst manifest
