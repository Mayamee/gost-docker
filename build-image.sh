#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env ]]; then
  echo "Error: .env not found. Copy .env.example to .env and set values." >&2
  exit 1
fi

if [[ ! -f config.yml ]]; then
  if [[ -f config.minimal.yml ]]; then
    echo "config.yml not found — copying from config.minimal.yml"
    cp config.minimal.yml config.yml
  else
    echo "Error: config.yml not found (and no config.minimal.yml to copy from)." >&2
    exit 1
  fi
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

: "${IMAGE_NAME:?IMAGE_NAME is required in .env}"
: "${PROXY_PORT:?PROXY_PORT is required in .env}"
: "${PROXY_USER:?PROXY_USER is required in .env}"
: "${PROXY_PASS:?PROXY_PASS is required in .env}"

IMAGE_TAG="${IMAGE_TAG:-latest}"
DIST_DIR="${ROOT_DIR}/dist"
ARCHIVE_NAME="${IMAGE_NAME}.tar"
ARCHIVE_PATH="${DIST_DIR}/${ARCHIVE_NAME}"

mkdir -p "${DIST_DIR}"

echo "Building image ${IMAGE_NAME}:${IMAGE_TAG}..."
docker build \
  --build-arg "PROXY_PORT=${PROXY_PORT}" \
  --build-arg "PROXY_USER=${PROXY_USER}" \
  --build-arg "PROXY_PASS=${PROXY_PASS}" \
  -t "${IMAGE_NAME}:${IMAGE_TAG}" .

echo "Saving image to ${ARCHIVE_PATH}..."
docker save -o "${ARCHIVE_PATH}" "${IMAGE_NAME}:${IMAGE_TAG}"

echo "Done: dist/${ARCHIVE_NAME} ($(du -h "${ARCHIVE_PATH}" | cut -f1))"
