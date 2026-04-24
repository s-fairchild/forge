FROM base AS builder

ARG MOTION_VERSION

ARG MOTION_SOURCE=/tmp/motion
ADD https://github.com/Motion-Project/motion.git#${MOTION_VERSION} ${MOTION_SOURCE}
WORKDIR ${MOTION_SOURCE}

ARG PREFIX
ARG FFMPEG_VERSION

COPY --from=docker.io/steve51516/ffmpeg:${FFMPEG_VERSION} \
    ${PREFIX}/lib/pkgconfig \
    ${PREFIX}/lib/pkgconfig

ARG BUILD_THREADS

RUN autoreconf -fiv \
    # https://motion-project.github.io/motionv5_build.html
    && ./configure \
        --with-ffmpeg=${PREFIX}/pkgconfig \
    && make -j${BUILD_THREADS} \
    && make install
