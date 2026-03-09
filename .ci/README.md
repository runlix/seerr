# Seerr CI Configuration

This directory contains configuration and scripts for the CI/CD pipeline.

## Files

### docker-matrix.json

Defines the build matrix for multi-architecture Docker images. See the [schema documentation](https://github.com/runlix/build-workflow/blob/main/schema/docker-matrix-schema.json) for details.

**Variants:**
- `latest-amd64` - Stable build for AMD64
- `latest-arm64` - Stable build for ARM64
- `debug-amd64` - Debug build for AMD64
- `debug-arm64` - Debug build for ARM64

### smoke-test.sh

Automated smoke test script that validates built Docker images before release.

**What it tests:**
- Container starts successfully
- No critical errors in logs
- Status endpoint responds (`/api/v1/status`)
- Root web endpoint is reachable
- Correct architecture is used

**Environment Variables:**
- `IMAGE_TAG` (required) - Docker image tag to test (set by workflow)
- `PLATFORM` (optional) - Platform to test (default: `linux/amd64`)

## Workflow Integration

The build workflow automatically:

1. On pull requests: builds all variants and runs smoke tests.
2. On merges to release branch: rebuilds all variants and runs smoke tests.
3. After tests pass: creates multi-arch manifests and pushes final tags.
