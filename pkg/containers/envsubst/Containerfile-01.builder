ARG IMAGE_TAG
FROM registry.access.redhat.com/ubi10-minimal:${IMAGE_TAG} AS builder

ARG TARGETOS
ARG TARGETARCH
ARG ENVSUBST_DOWNLOAD_ARCH
ARG ENVSUBST_VERSION
ARG ENVSUBST_SOURCE

WORKDIR /tmp
# ADD --chmod=551 ${ENVSUBST_SOURCE}/releases/download/${ENVSUBST_VERSION}/envsubst-${TARGETOS}-${ENVSUBST_DOWNLOAD_ARCH} /usr/local/bin/envsubst
RUN if [ "${TARGETARCH}" == "amd64" ]; then \
        # https://github.com/a8m/envsubst/releases/download/v1.4.3/envsubst-Linux-x86_64
        download_suffix=${TARGETOS}-x86_64; \
    else \
        # https://github.com/a8m/envsubst/releases/download/v1.4.3/envsubst-Linux-arm64
        download_suffix=${TARGETOS}-${TARGETARCH}; \
    fi \
    && curl -L \
            ${ENVSUBST_SOURCE}/releases/download/${ENVSUBST_VERSION}/envsubst-${download_suffix} \
            -o envsubst \
    # The upstream md5 digest is improperly formatted for md5sum --check
    && checksum="$(curl -L ${ENVSUBST_SOURCE}/releases/download/${ENVSUBST_VERSION}/envsubst-${download_suffix}.md5)" \
    && echo "$checksum envsubst" > envsubst.md5 \
    && md5sum --check envsubst.md5
