ARG IMAGE_REGISTRY
ARG IMAGE_REPOSITORY
ARG IMAGE_TAG
FROM --platform=${BUILDPLATFORM} ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG} AS builder

ARG TZ_COUNTRY
ARG TZ_CITY

# TODO set the required env variable to enable QSV support.
# OR setup intel k8s plugin https://github.com/intel/intel-device-plugins-for-kubernetes

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
        # The packages being installed want to know the timezone.
        ln -s /usr/share/zoneinfo/${TZ_COUNTRY}/${TZ_CITY} /etc/localtime \
        # Update everything first.
        && DEBIAN_FRONTEND=noninteractive \
            apt-get update \
            && apt-get upgrade -y \
      # Install QSV driver packages for intel GPU acceleration.
        && DEBIAN_FRONTEND=noninteractive \
            apt-get install --no-install-recommends -y \
            ffmpeg intel-media-va-driver-non-free libmfx-dev intel-gpu-tools vainfo
