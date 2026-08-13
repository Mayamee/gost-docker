#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

if [[ ! -f .env.test ]]; then
  echo "✗ Ошибка: файл .env.test не найден." >&2
  exit 1
fi

if [[ ! -f config.yml ]]; then
  if [[ -f config.minimal.yml ]]; then
    echo "config.yml не найден — копирую из config.minimal.yml"
    cp config.minimal.yml config.yml
  else
    echo "✗ Ошибка: config.yml не найден (и нет config.minimal.yml)." >&2
    exit 1
  fi
fi

set -a
# shellcheck disable=SC1091
source .env.test
set +a

: "${IMAGE_NAME:?IMAGE_NAME обязателен в .env.test}"
: "${PROXY_PORT:?PROXY_PORT обязателен в .env.test}"
: "${PROXY_USER:?PROXY_USER обязателен в .env.test}"
: "${PROXY_PASS:?PROXY_PASS обязателен в .env.test}"

PROXY_HOST="${PROXY_HOST:-127.0.0.1}"
TEST_URL="${TEST_URL:-https://github.com}"
CURL_OPTS=(--silent --show-error --output /dev/null --connect-timeout 5 --max-time 15)

# Уникальные имена только для этого прогона — чужие ресурсы не трогаем
RUN_ID="$$"
TEST_IMAGE="${IMAGE_NAME}:testconnect-${RUN_ID}"
TEST_CONTAINER="gost-testconnect-${RUN_ID}"
DIST_DIR="${ROOT_DIR}/dist"
ARCHIVE_PATH="${DIST_DIR}/${IMAGE_NAME}.tar"

CREATED_IMAGE=0
CREATED_CONTAINER=0
CREATED_ARCHIVE=0
PASSED=0
FAILED=0

log() {
  printf '%s\n' "$*"
}

log_section() {
  printf '\n▶ %s\n' "$*"
}

pass() {
  log "  ✓ $*"
  PASSED=$((PASSED + 1))
}

fail() {
  log "  ✗ $*"
  FAILED=$((FAILED + 1))
}

# Удаляет только ресурсы этого запуска: контейнер, тестовый образ и dist/<IMAGE_NAME>.tar.
# Архивы сборки (dist/<IMAGE_NAME>.amd64.tar / .arm64.tar) не трогаем.
cleanup() {
  local ec=$?
  log_section "Очистка"

  if [[ "${CREATED_CONTAINER}" -eq 1 ]]; then
    log "  • удаляю контейнер ${TEST_CONTAINER}"
    docker rm -f "${TEST_CONTAINER}" >/dev/null 2>&1 || true
  else
    log "  • контейнер не создавался — пропускаю"
  fi

  if [[ "${CREATED_IMAGE}" -eq 1 ]]; then
    log "  • удаляю образ ${TEST_IMAGE}"
    docker rmi -f "${TEST_IMAGE}" >/dev/null 2>&1 || true
  else
    log "  • образ не создавался — пропускаю"
  fi

  if [[ "${CREATED_ARCHIVE}" -eq 1 ]]; then
    log "  • удаляю тестовый артефакт dist/${IMAGE_NAME}.tar"
    rm -f "${ARCHIVE_PATH}"
    if [[ -d "${DIST_DIR}" ]] && [[ -z "$(ls -A "${DIST_DIR}" 2>/dev/null || true)" ]]; then
      rmdir "${DIST_DIR}" 2>/dev/null || true
    fi
  else
    log "  • тестовый артефакт не создавался — пропускаю"
  fi

  return "${ec}"
}

trap cleanup EXIT

# Выполняет HTTP-запрос через прокси. Печатает: "<код_выхода_curl> <http_код>"
request_via_proxy() {
  local user="$1"
  local pass="$2"
  local code
  local curl_status=0

  code=$(curl "${CURL_OPTS[@]}" \
    -w "%{http_code}" \
    -x "http://${user}:${pass}@${PROXY_HOST}:${PROXY_PORT}" \
    "${TEST_URL}" 2>/dev/null) || curl_status=$?

  printf '%s %s' "${curl_status}" "${code}"
}

log "════════════════════════════════════════"
log "  Проверка прокси gost"
log "════════════════════════════════════════"
log "• Цель:     ${TEST_URL}"
log "• Прокси:   ${PROXY_HOST}:${PROXY_PORT} (.env.test)"
log "• Артефакт: dist/${IMAGE_NAME}.tar"

# ---------------------------------------------------------------------------
# Подготовка среды: сборка → сохранение в dist/ → load → контейнер
# ---------------------------------------------------------------------------
log_section "Подготовка среды"

log "  ◦ собираю образ ${TEST_IMAGE} (config.yml)"
docker build \
  --build-arg "PROXY_PORT=${PROXY_PORT}" \
  --build-arg "PROXY_USER=${PROXY_USER}" \
  --build-arg "PROXY_PASS=${PROXY_PASS}" \
  -t "${TEST_IMAGE}" \
  . >/dev/null
CREATED_IMAGE=1
log "  ✓ образ собран"

mkdir -p "${DIST_DIR}"
log "  ◦ сохраняю артефакт ${ARCHIVE_PATH}"
docker save -o "${ARCHIVE_PATH}" "${TEST_IMAGE}"
CREATED_ARCHIVE=1
log "  ✓ артефакт записан"

# ---------------------------------------------------------------------------
# Кейс 0. Артефакт dist/<IMAGE_NAME>.tar должен существовать и грузиться
# ---------------------------------------------------------------------------
log_section "Кейс 0. Артефакт dist/${IMAGE_NAME}.tar валиден"

log "  ◦ Arrange: ARCHIVE_PATH=${ARCHIVE_PATH}"

if [[ -f "${ARCHIVE_PATH}" ]]; then
  pass "Assert: файл dist/${IMAGE_NAME}.tar существует"
else
  fail "Assert: файл dist/${IMAGE_NAME}.tar не найден"
fi

if [[ -s "${ARCHIVE_PATH}" ]]; then
  pass "Assert: dist/${IMAGE_NAME}.tar не пустой ($(du -h "${ARCHIVE_PATH}" | cut -f1))"
else
  fail "Assert: dist/${IMAGE_NAME}.tar пустой или отсутствует"
fi

log "  → Act: docker rmi ${TEST_IMAGE} (проверка load из tar)"
docker rmi -f "${TEST_IMAGE}" >/dev/null 2>&1 || true

log "  → Act: docker load -i ${ARCHIVE_PATH}"
if load_out=$(docker load -i "${ARCHIVE_PATH}" 2>&1); then
  log "  → Act: ${load_out}"
  pass "Assert: docker load успешно загрузил образ из dist/${IMAGE_NAME}.tar"
  CREATED_IMAGE=1
else
  fail "Assert: docker load не смог загрузить dist/${IMAGE_NAME}.tar"
  log "✗ Без загруженного образа дальнейшие кейсы невозможны."
  exit 1
fi

if docker image inspect "${TEST_IMAGE}" >/dev/null 2>&1; then
  pass "Assert: образ ${TEST_IMAGE} доступен после load"
else
  fail "Assert: образ ${TEST_IMAGE} не найден после load"
  exit 1
fi

log "  ◦ запускаю контейнер ${TEST_CONTAINER} (-p 127.0.0.1:${PROXY_PORT}:${PROXY_PORT})"
docker run -d \
  --name "${TEST_CONTAINER}" \
  -p "127.0.0.1:${PROXY_PORT}:${PROXY_PORT}" \
  "${TEST_IMAGE}" >/dev/null
CREATED_CONTAINER=1

# Ждём, пока прокси начнёт слушать порт
for _ in $(seq 1 20); do
  if docker logs "${TEST_CONTAINER}" 2>&1 | grep -q "listening on"; then
    break
  fi
  sleep 0.25
done

if ! docker logs "${TEST_CONTAINER}" 2>&1 | grep -q "listening on"; then
  log "  ✗ контейнер не поднял listener"
  docker logs "${TEST_CONTAINER}" >&2 || true
  exit 1
fi
log "  ✓ контейнер из артефакта слушает ${PROXY_HOST}:${PROXY_PORT}"

# ---------------------------------------------------------------------------
# Кейс 1. Валидные PROXY_* — запрос должен пройти через прокси
# ---------------------------------------------------------------------------
log_section "Кейс 1. При валидных PROXY_PORT / PROXY_USER / PROXY_PASS запрос проксируется"

# Arrange — подготовка данных
log "  ◦ Arrange: PROXY_HOST=${PROXY_HOST}"
log "  ◦ Arrange: PROXY_PORT=${PROXY_PORT}"
log "  ◦ Arrange: PROXY_USER=${PROXY_USER}"
log "  ◦ Arrange: PROXY_PASS=<задан>"
log "  ◦ Arrange: TEST_URL=${TEST_URL}"
valid_user="${PROXY_USER}"
valid_pass="${PROXY_PASS}"

# Act — выполнение действия
log "  → Act: GET ${TEST_URL} через http://${valid_user}:***@${PROXY_HOST}:${PROXY_PORT}"
read -r valid_curl_status valid_http_code <<<"$(request_via_proxy "${valid_user}" "${valid_pass}")"
log "  → Act: код выхода curl=${valid_curl_status}, HTTP=${valid_http_code}"

# Assert — проверка результата
if [[ "${valid_curl_status}" == "0" ]]; then
  pass "Assert: curl завершился без ошибки"
else
  fail "Assert: ожидался код выхода curl=0, получен ${valid_curl_status}"
fi

if [[ "${valid_http_code}" =~ ^[23][0-9][0-9]$ ]]; then
  pass "Assert: прокси вернул успешный ответ (HTTP ${valid_http_code})"
else
  fail "Assert: ожидался HTTP 2xx/3xx при валидных учётных данных, получен ${valid_http_code}"
fi

# ---------------------------------------------------------------------------
# Кейс 2. Неверные credentials — запрос не должен пройти
# ---------------------------------------------------------------------------
log_section "Кейс 2. При неверных credentials запрос не проксируется"

# Arrange — подготовка данных с заведомо неверным паролем
wrong_user="${PROXY_USER}"
wrong_pass="wrong-${PROXY_PASS}-invalid"
log "  ◦ Arrange: PROXY_HOST=${PROXY_HOST}"
log "  ◦ Arrange: PROXY_PORT=${PROXY_PORT}"
log "  ◦ Arrange: PROXY_USER=${wrong_user}"
log "  ◦ Arrange: PROXY_PASS=<неверный>"
log "  ◦ Arrange: TEST_URL=${TEST_URL}"

# Act — выполнение действия
log "  → Act: GET ${TEST_URL} через http://${wrong_user}:***@${PROXY_HOST}:${PROXY_PORT}"
read -r bad_curl_status bad_http_code <<<"$(request_via_proxy "${wrong_user}" "${wrong_pass}")"
log "  → Act: код выхода curl=${bad_curl_status}, HTTP=${bad_http_code}"

# Assert — при ошибке аутентификации ожидаем отказ (curl≠0 и/или 401/407/000)
if [[ "${bad_curl_status}" -ne 0 || "${bad_http_code}" == "407" || "${bad_http_code}" == "401" || "${bad_http_code}" == "000" ]]; then
  pass "Assert: прокси отклонил запрос (curl=${bad_curl_status}, HTTP=${bad_http_code})"
else
  fail "Assert: запрос с неверным паролем неожиданно прошёл (curl=${bad_curl_status}, HTTP=${bad_http_code})"
fi

if [[ "${bad_http_code}" =~ ^[23][0-9][0-9]$ ]]; then
  fail "Assert: при неверном пароле не должно быть HTTP 2xx/3xx, получен ${bad_http_code}"
else
  pass "Assert: успешного ответа upstream нет (HTTP ${bad_http_code})"
fi

# ---------------------------------------------------------------------------
log_section "Итог"
log "  ✓ Успешно: ${PASSED}"
log "  ✗ Провалено: ${FAILED}"

if [[ "${FAILED}" -gt 0 ]]; then
  log "✗ Есть проваленные проверки."
  exit 1
fi

log "✓ Все тест-кейсы прошли."
