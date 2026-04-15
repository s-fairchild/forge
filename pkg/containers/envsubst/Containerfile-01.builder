ARG IMAGE_REGISTRY
ARG IMAGE_REPOSITORY
ARG IMAGE_TAG
FROM --platform=${BUILDPLATFORM} ${IMAGE_REGISTRY}/${IMAGE_REPOSITORY}:${IMAGE_TAG} AS builder

RUN microdnf makecache \
        && microdnf install -y gettext-envsubst \
        && microdnf clean all
