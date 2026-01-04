ARG IMAGE_REGISTRY
ARG IMAGE_REPOSITORY
ARG IMAGE_TAG
FROM ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG} AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
      DEBIAN_FRONTEND=noninteractive apt-get update \
      # Install all common build packages
      && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
            # Tools
            automake autoconf autopoint libtool build-essential yasm git cmake pkgconf gettext \
            # General libraries
            libva-dev libwebp-dev libtwolame-dev libxvidcore-dev libzimg-dev libzvbi-dev \
            libdrm-dev libwebp7 libwebpmux3 libwebpdemux2 libxvidcore4 libxml2-dev libva-drm2 \
            libxcb-shm0-dev libxcb1-dev libasound2-dev libsndio-dev libsdl2-dev libxv-dev \
            libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libavdevice-dev \
            # Intel OpenCL
            # Starting from Ubuntu 19.04 Intel media stack components are available for installation via apt-get.
            # Reference: [Intel media stack on Ubuntu](https://github.com/Intel-Media-SDK/MediaSDK/wiki/Intel-media-stack-on-Ubuntu)
            libigc-dev libigc1 libigdfcl-dev opencl-headers clinfo ocl-icd-opencl-dev libmfx-dev \
            libvulkan-dev libvulkan-memory-allocator-dev libgulkan-dev vulkan-utility-libraries-dev \
            libmfx1 libmfx-tools libvpx9 libvpx-dev \
            # For build ffplay (as part of ffmpeg) you also need to install additional dependencies:
            libsdl2-dev x264 libx264-dev libx264-164 libheif-plugin-x265 libx265-199 libx265-dev x265 \
            # https://github.com/Intel-Media-SDK/MediaSDK/wiki/Intel-media-stack-on-Ubuntu#available-drivers
            intel-media-va-driver-non-free \
            # Packages I may need to add
      && DEBIAN_FRONTEND=noninteractive apt-get clean \
      && rm -rf /var/lib/apt/lists/*
