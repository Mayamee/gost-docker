#!/bin/sh
set -eu

: "${PROXY_PORT:?PROXY_PORT is required}"
: "${PROXY_USER:?PROXY_USER is required}"
: "${PROXY_PASS:?PROXY_PASS is required}"

escape_sed() {
  printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'
}

PORT_ESC=$(escape_sed "$PROXY_PORT")
USER_ESC=$(escape_sed "$PROXY_USER")
PASS_ESC=$(escape_sed "$PROXY_PASS")

sed \
  -e "s|__PROXY_PORT__|${PORT_ESC}|g" \
  -e "s|__PROXY_USER__|${USER_ESC}|g" \
  -e "s|__PROXY_PASS__|${PASS_ESC}|g" \
  /tmp/gost.yml.template > /config.yml
