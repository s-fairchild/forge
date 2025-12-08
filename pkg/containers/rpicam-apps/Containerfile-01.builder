ARG IMAGE_REGISTRY
ARG IMAGE_REPOSITORY
ARG IMAGE_TAG
FROM --platform=arm64 ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG} AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
      DEBIAN_FRONTEND=noninteractive apt-get update \
      # Install all common build packages
      && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
                        # build tools
                        meson cmake build-essential pkg-config git \
                        # rpicam-apps dependencies
                        libavcodec-dev libjpeg-dev libtiff5-dev libpng-dev \
                        libavdevice-dev libavformat-dev libswresample-dev \
                        libboost-program-options1.88-dev libdrm-dev libexif-dev ninja-build
