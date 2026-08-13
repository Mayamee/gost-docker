#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

ENV_FILE="${ENV_FILE:-.env}"

if [[ ! -f "${ENV_FILE}" ]]; then
  echo "Error: ${ENV_FILE} not found. Copy .env.example to .env and set values." >&2
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
# shellcheck source=.env.example
source "${ENV_FILE}"
set +a

: "${IMAGE_NAME:?IMAGE_NAME is required in ${ENV_FILE}}"
: "${PROXY_PORT:?PROXY_PORT is required in ${ENV_FILE}}"
: "${PROXY_USER:?PROXY_USER is required in ${ENV_FILE}}"
: "${PROXY_PASS:?PROXY_PASS is required in ${ENV_FILE}}"

IMAGE_TAG="${IMAGE_TAG:-latest}"
DIST_DIR="${ROOT_DIR}/dist"
ARCHES=(amd64 arm64)

mkdir -p "${DIST_DIR}"

for arch in "${ARCHES[@]}"; do
  binary="gost-linux-${arch}"
  if [[ ! -f "${binary}" ]]; then
    echo "Error: ${binary} not found in ${ROOT_DIR}." >&2
    exit 1
  fi
done

for arch in "${ARCHES[@]}"; do
  platform="linux/${arch}"
  tag="${IMAGE_NAME}:${IMAGE_TAG}-${arch}"
  archive_name="${IMAGE_NAME}.${arch}.tar"
  archive_path="${DIST_DIR}/${archive_name}"

  echo "Building image ${tag} (${platform})..."
  docker build \
    --platform "${platform}" \
    --build-arg "TARGETARCH=${arch}" \
    --build-arg "PROXY_PORT=${PROXY_PORT}" \
    --build-arg "PROXY_USER=${PROXY_USER}" \
    --build-arg "PROXY_PASS=${PROXY_PASS}" \
    -t "${tag}" \
    .

  echo "Saving image to ${archive_path}..."
  docker save -o "${archive_path}" "${tag}"
  echo "Done: dist/${archive_name} ($(du -h "${archive_path}" | cut -f1))"
done
