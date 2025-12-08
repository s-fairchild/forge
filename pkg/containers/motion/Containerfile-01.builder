ARG IMAGE_REGISTRY
ARG IMAGE_REPOSITORY
ARG IMAGE_TAG
FROM ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG} AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
      DEBIAN_FRONTEND=noninteractive apt-get update && apt-get upgrade -y \
      # Install all common build packages
      && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
            automake autoconf autopoint libtool build-essential git cmake pkgconf gettext \
            libva-dev libmfx-gen-dev libwebp-dev \
            # Required packages
            libzip-dev libjpeg-dev libmicrohttpd-dev libavformat-dev \
            libavcodec-dev libavutil-dev libswscale-dev libavdevice-dev \
            # # These driver dev files maybe needed, we'll see
            # Optional packages
            # SQLite3 database functionality
            libsqlite3-dev \
            # Webp Image Support
            libwebp-dev \
            # FFMpeg Functionality(Required for creating movies, using network cameras, etc.)
            libavformat-dev libavcodec-dev libavutil-dev libswscale-dev libavdevice-dev
