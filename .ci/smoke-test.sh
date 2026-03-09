#!/usr/bin/env bash
set -e
set -o pipefail

# Smoke test for Seerr Docker image
# This script receives IMAGE_TAG from the workflow environment

IMAGE="${IMAGE_TAG}"
PLATFORM="${PLATFORM:-linux/amd64}"
CONTAINER_NAME="seerr-smoke-test-${RANDOM}"
SEERR_PORT="5055"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Seerr Smoke Test${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Image: ${IMAGE}"
echo "Platform: ${PLATFORM}"
echo ""

if [ -z "${IMAGE}" ] || [ "${IMAGE}" = "null" ]; then
  echo -e "${RED}ERROR: IMAGE_TAG environment variable is not set${NC}"
  exit 1
fi

CONFIG_DIR=$(mktemp -d)
chmod 777 "${CONFIG_DIR}"
echo "Config directory: ${CONFIG_DIR}"
echo ""

cleanup() {
  echo ""
  echo -e "${YELLOW}Cleaning up...${NC}"

  if docker ps -a | grep -q "${CONTAINER_NAME}"; then
    echo "Saving container logs..."
    docker logs "${CONTAINER_NAME}" > /tmp/seerr-smoke-test.log 2>&1 || true
    echo "Logs saved to: /tmp/seerr-smoke-test.log"
  fi

  docker stop "${CONTAINER_NAME}" 2>/dev/null || true
  docker rm "${CONTAINER_NAME}" 2>/dev/null || true

  if [ -d "${CONFIG_DIR}" ]; then
    chmod -R 777 "${CONFIG_DIR}" 2>/dev/null || true
    rm -rf "${CONFIG_DIR}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo -e "${BLUE}Starting container...${NC}"
if ! docker run \
  --pull=never \
  --platform="${PLATFORM}" \
  --name "${CONTAINER_NAME}" \
  -v "${CONFIG_DIR}:/app/config" \
  -p "${SEERR_PORT}:5055" \
  -e PORT=5055 \
  -e TZ=UTC \
  -d \
  "${IMAGE}"; then
  echo -e "${RED}Failed to start container${NC}"
  exit 1
fi

echo -e "${GREEN}Container started${NC}"
echo ""

echo -e "${BLUE}Waiting for Seerr to initialize...${NC}"
sleep 20

echo -e "${BLUE}Checking container status...${NC}"
if ! docker ps | grep -q "${CONTAINER_NAME}"; then
  echo -e "${RED}Container exited unexpectedly${NC}"
  docker logs "${CONTAINER_NAME}" 2>&1 || true
  exit 1
fi

LOGS=$(docker logs "${CONTAINER_NAME}" 2>&1 || true)
FATAL_COUNT=$(echo "$LOGS" | grep -ciE "fatal|panic|exception|error:" || true)
if [ "${FATAL_COUNT}" -gt 0 ]; then
  echo -e "${RED}Found ${FATAL_COUNT} critical error(s) in logs${NC}"
  echo "$LOGS" | grep -iE "fatal|panic|exception|error:" | head -10
  exit 1
fi

echo -e "${GREEN}No critical startup errors in logs${NC}"
echo ""

echo -e "${BLUE}Testing status endpoint...${NC}"
STATUS_URL="http://localhost:${SEERR_PORT}/api/v1/status"
MAX_ATTEMPTS=24
ATTEMPT=0
STATUS_OK=false

while [ $ATTEMPT -lt $MAX_ATTEMPTS ]; do
  ATTEMPT=$((ATTEMPT + 1))
  if curl -fsSL --max-time 5 "${STATUS_URL}" -o /dev/null 2>/dev/null; then
    STATUS_OK=true
    break
  fi
  echo "Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: waiting for status endpoint..."
  sleep 5
done

if [ "${STATUS_OK}" = false ]; then
  echo -e "${RED}Status endpoint check failed after ${MAX_ATTEMPTS} attempts${NC}"
  docker logs "${CONTAINER_NAME}" 2>&1 | tail -30 || true
  exit 1
fi
echo -e "${GREEN}Status endpoint responding (${STATUS_URL})${NC}"

ROOT_URL="http://localhost:${SEERR_PORT}/"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "${ROOT_URL}" 2>/dev/null || echo "000")
if [ "${HTTP_CODE}" = "200" ] || [ "${HTTP_CODE}" = "302" ]; then
  echo -e "${GREEN}Web endpoint responding (${ROOT_URL}) HTTP ${HTTP_CODE}${NC}"
else
  echo -e "${YELLOW}Web endpoint returned HTTP ${HTTP_CODE} (non-critical)${NC}"
fi

IMAGE_ARCH=$(docker image inspect "${IMAGE}" | jq -r '.[0].Architecture')
EXPECTED_ARCH=$(echo "${PLATFORM}" | cut -d'/' -f2)
if [ "${IMAGE_ARCH}" != "${EXPECTED_ARCH}" ] && [ "${IMAGE_ARCH}" != "null" ]; then
  echo -e "${RED}Architecture mismatch: expected ${EXPECTED_ARCH}, got ${IMAGE_ARCH}${NC}"
  exit 1
fi

echo ""
echo -e "${GREEN}Smoke test passed${NC}"
echo "Summary:"
echo "  - Container startup: OK"
echo "  - Status endpoint: OK"
echo "  - Architecture: ${IMAGE_ARCH}"
