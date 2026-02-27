ARG IMAGE_REGISTRY
ARG IMAGE_REPOSITORY
ARG IMAGE_TAG
FROM --platform=linux/arm64 ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG} AS builder

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
      DEBIAN_FRONTEND=noninteractive apt-get update \
      # Install all common build packages
      && DEBIAN_FRONTEND=noninteractive apt-get install --no-install-recommends -y \
                        # Shared build tools
                        meson cmake build-essential \
                        python3-pip git \
                        # libcamera dependencies
                        # References:
                        #   * https://www.raspberrypi.com/documentation/computers/camera_software.html#building-libcamera
                        #   * https://github.com/raspberrypi/libcamera/tree/main?tab=readme-ov-file#dependencies
                        #
                        # C++ toolchain (required)
                        # either g++ or clang
                        gcc \
                        # libcamera core (required)
                        libyaml-dev python3-yaml python3-ply python3-jinja2 \
                        # Add IPA module signing support (recommended)
                        libgnutls28-dev openssl \
                        ## Add python bindings for pycamera2 api support (optional)
                        # libpython3-dev pybind11-dev \
                        libboost-dev libtiff5-dev pybind11-dev \
                        qtbase5-dev libqt5core5a libqt5gui5 libqt5widgets5 \
                        # Add support for device hotplug enumeration (optional)
                        libudev-dev \
                        # libav codec support. Uses hardware acceleration on RPI4
                        libavcodec-dev libavdevice-dev libavformat-dev libswresample-dev \
                        # Other libcamera dependencies
                        libavcodec-dev libjpeg-dev libtiff5-dev libpng-dev \
                        libavdevice-dev libavformat-dev libswresample-dev \
                        libboost-program-options-dev libdrm-dev libexif-dev ninja-build \
                        libglib2.0-dev libgstreamer-plugins-base1.0-dev
