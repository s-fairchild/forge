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
ARG CONFIGURE_ENV
ARG CONFIGURE_LICENSE
ARG MAKE_EXCLUDE
ARG MAKE_HWACCELS
ARG MAKE_EXTERNAL_LIBRARIES

RUN ./configure --arch=${TARGETARCH} \
                --target-os=${TARGETOS} \
                --prefix=${PREFIX} \
                --extra-version=${FFMPEG_VERSION} \
                ${CONFIGURE_GENERAL} \
                ${CONFIGURE_ENV} \
                # External library support 
                ${MAKE_EXTERNAL_LIBRARIES} \
                # Intel GPU options
                ${MAKE_HWACCELS} \
                # Excluded options
                ${MAKE_EXCLUDE} \
                # Licensing options
                ${CONFIGURE_LICENSE} \
    && make -j"${BUILD_THREADS}" \
    && make install
