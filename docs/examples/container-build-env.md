# Example: Container Build Environment Files

Container images in `pkg/containers/` are built via `pkg/containers/Makefile`. Each image has a corresponding environment file under `hack/env/podman/build/` that declares version tags, build arguments, and multi-stage build context references.

All build targets in this document are run as:

```bash
make -C pkg/containers <target>
```

---

## How the Build System Works

The build pipeline reads three sources of configuration:

| Source | Location | Purpose |
|--------|----------|---------|
| Constants | `hack/lib/podman/build/constants.env` | Image names, registry URLs, common tag constants |
| Per-image env | `hack/env/podman/build/<image>.env` | Version tags, build args, multi-stage contexts |
| Build args file | `pkg/containers/<image>/argfile.conf` | Key=value build args passed to `podman build --build-arg-file` |

`podman-build.sh` sources the constants file and per-image env file, then invokes `podman build` with the resolved build args, tags, and context paths.

The constants file defines the shared image name variables used by build env files:

| Constant | Value | Used by |
|----------|-------|---------|
| `IMAGE_FFMPEG` | `ffmpeg` | ffmpeg targets |
| `IMAGE_MOTION` | `motion` | motion targets |
| `IMAGE_LIBCAMERA` | `libcamera` | libcamera targets |
| `IMAGE_RPICAM_APPS` | `rpicam-apps` | rpicam-apps targets |
| `IMAGE_BTRFS_PROGS` | `btrfs-progs` | btrfs-progs targets |
| `IMAGE_ENVSUBST` | `envsubst` | envsubst targets |
| `REMOTE_REPOSITORY` | `docker.io/steve51516` | push targets |

---

## `btrfs-progs` (mirrors `example.env`)

A fixed Alpine-based build with no version override. The env file sets `IMAGE_TAG_PRIMARY=latest` and maps a single `ALPINE_IMAGE` build arg.

```bash
# Build
make -C pkg/containers container-build-btrfs-progs
```

Check the resolved build args:

```bash
cat pkg/containers/btrfs-progs/argfile.conf
```

---

## `ffmpeg`

ffmpeg is built directly in the Makefile target without using `podman-build.sh`. The version is read from `argfile.conf`.

```bash
# Build
make -C pkg/containers container-build-ffmpeg

# Tag (adds :latest and docker.io remote tags)
make -C pkg/containers container-tag-ffmpeg

# Build + tag
make -C pkg/containers container-build-tag-ffmpeg

# Push (requires prior tag)
make -C pkg/containers container-push-ffmpeg

# Build + tag + push in one step
make -C pkg/containers container-build-push-ffmpeg
```

Inspect the version that will be used:

```bash
grep "^FFMPEG_VERSION" pkg/containers/ffmpeg/argfile.conf
```

---

## `motion`

motion depends on the ffmpeg image for its builder stage. Build ffmpeg first, then motion.

```bash
# Build ffmpeg first (if not already built)
make -C pkg/containers container-build-ffmpeg

# Build motion
make -C pkg/containers container-build-motion

# Build + tag + push
make -C pkg/containers container-build-push-motion
```

Inspect versions:

```bash
grep "^MOTION_VERSION=" pkg/containers/motion/argfile.conf
grep "^FFMPEG_VERSION"  pkg/containers/ffmpeg/argfile.conf
```

**Override the motion version at build time:**

```bash
# Edit argfile.conf before building, or use environment override if supported
MOTION_VERSION_OVERRIDE=5.1 make -C pkg/containers container-build-motion
```

---

## `envsubst`

Multi-arch build (amd64 + arm64) using podman manifest. No external dependencies.

```bash
# Build (creates a multi-arch manifest)
make -C pkg/containers container-build-envsubst

# Push manifest
make -C pkg/containers container-push-envsubst

# Build + push
make -C pkg/containers container-build-push-envsubst
```

Inspect the version:

```bash
cat pkg/containers/envsubst/argfile.conf
```

---

## `libcamera`

libcamera is an arm64-only build. The version is controlled by `LIBCAMERA_VERSION_GIT_TAG_VALUE` in the env file, which supports an override via `LIBCAMERA_VERSION_GIT_TAG_OVERRIDE`.

**Default version** (from `hack/env/podman/build/libcamera.env`):

```bash
make -C pkg/containers container-build-libcamera
```

**Override the git tag:**

```bash
LIBCAMERA_VERSION_GIT_TAG_OVERRIDE=v0.7.0+rpt20260205 \
  make -C pkg/containers container-build-libcamera
```

Inspect the effective version:

```bash
grep "LIBCAMERA_VERSION" hack/env/podman/build/libcamera.env
```

---

## `rpicam-apps`

rpicam-apps depends on the libcamera image via a `BUILD_CONTEXTS` reference. Build libcamera first.

**Build sequence:**

```bash
# 1. Build libcamera first
make -C pkg/containers container-build-libcamera

# 2. Build rpicam-apps (uses the locally built libcamera image as a build context)
make -C pkg/containers container-build-rpicam-apps
```

**Override the rpicam-apps version:**

```bash
RPICAM_APPS_VERSION_TAG_OVERRIDE=v1.11.2 \
  make -C pkg/containers container-build-rpicam-apps
```

Inspect the env file to see the `BUILD_CONTEXTS` chain and version defaults:

```bash
cat hack/env/podman/build/rpicam-apps.env
```

---

## Adding a New Image

1. Create `pkg/containers/<name>/` with a `Containerfile` (or multi-stage `Containerfile-01.base`, etc.) and an `argfile.conf`.
2. Create `hack/env/podman/build/<name>.env` declaring `BUILD_ARGS`, `IMAGE_TAG_PRIMARY`, and optionally `BUILD_CONTEXTS` for multi-stage dependencies.
3. Add a `container-build-<name>` target to `pkg/containers/Makefile` following the existing pattern.
4. If the image must be pushed, add `container-tag-<name>`, `container-push-<name>`, and `container-build-push-<name>` targets.
