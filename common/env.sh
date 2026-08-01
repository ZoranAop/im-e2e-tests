#!/usr/bin/env bash
# Environment Configuration Loader
# Loads .env file if present, applies defaults

set -euo pipefail

ENV_FILE="${ENV_FILE:-.env}"

load_env() {
    if [ -f "${ENV_FILE}" ]; then
        while IFS='=' read -r key value; do
            key=$(echo "${key}" | xargs)
            if [ -z "${key}" ] || [ "${key:0:1}" = "#" ]; then continue; fi
            value=$(echo "${value}" | xargs)
            value="${value%\"}"; value="${value#\"}"
            value="${value%\'}"; value="${value#\'}"
            export "${key}=${value}"
        done < "${ENV_FILE}"
    fi
}

# Auto-load on source
load_env
