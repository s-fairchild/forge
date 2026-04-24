FROM base AS builder

ARG TARGETARCH
ARG TARGETOS
ARG BUILD_THREADS
ARG PREFIX

ARG FFMPEG_VERSION
ARG BUILD_TARGET="$PREFIX/src/ffmpeg"
ADD https://github.com/FFmpeg/FFmpeg.git#${FFMPEG_VERSION} ${BUILD_TARGET}
WORKDIR ${BUILD_TARGET}

ARG CONFIGURE_GENERAL
ARG CONFIGURE_LICENSE
ARG MAKE_EXCLUDE

# TODO split this up by TARGETARCH (amd64 == x86_64)
RUN ./configure --arch=x86_64 \
                --target-os=${TARGETOS} \
                --prefix=${PREFIX} \
                --extra-version=${FFMPEG_VERSION} \
                # Licensing options
                ${CONFIGURE_LICENSE} \
                --enable-nonfree \
                ${CONFIGURE_GENERAL} \
                --env="LIBVA_DRIVER_NAME=iHD" \
                # Excluded options
                ${MAKE_EXCLUDE} \
                # Intel GPU options
                --enable-libvpx --enable-libmfx --enable-opencl --enable-libdrm \
                --enable-vaapi --enable-libx264 --enable-libx265 --enable-libwebp \
                --enable-postproc --enable-libxml2 --enable-libxvid --enable-libzimg \
                --enable-libzvbi --enable-gray --enable-libtwolame \
    && make -j"${BUILD_THREADS}" \
    && make install
