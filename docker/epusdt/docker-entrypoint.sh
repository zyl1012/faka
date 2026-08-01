#!/bin/sh
set -eu

source_config="${EPUSDT_CONFIG_SOURCE:-/app/conf/epusdt.env}"
runtime_config="${EPUSDT_CONFIG_RUNTIME:-/tmp/epusdt.env}"

if [ ! -f "$source_config" ]; then
  echo "EPUSDT config not found: $source_config" >&2
  exit 1
fi

if [ -n "${EPUSDT_PUBLIC_URL:-}" ]; then
  if ! grep -q '^app_uri=' "$source_config"; then
    echo "EPUSDT config is missing app_uri: $source_config" >&2
    exit 1
  fi
  sed "s|^app_uri=.*$|app_uri=${EPUSDT_PUBLIC_URL}|" "$source_config" > "$runtime_config"
else
  cp "$source_config" "$runtime_config"
fi

chmod 0600 "$runtime_config"
export EPUSDT_CONFIG="$runtime_config"

exec "$@"
