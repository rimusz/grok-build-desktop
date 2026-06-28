#!/usr/bin/env bash
# Load KEY=value lines from .env without overriding variables already exported
# (e.g. from `make release SIGN_IDENTITY=...` or CI).

load_dotenv() {
  local env_file="${1:-.env}"
  [ -f "$env_file" ] || return 0

  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*# ]] && continue
    [[ "$line" =~ ^[[:space:]]*$ ]] && continue
    [[ "$line" != *"="* ]] && continue

    local key="${line%%=*}"
    local value="${line#*=}"
    key="${key#"${key%%[![:space:]]*}"}"
    key="${key%"${key##*[![:space:]]}"}"

    # Keep explicit environment overrides (make/CI) over .env defaults.
    if [ -z "${!key+x}" ]; then
      export "$key=$value"
    fi
  done < "$env_file"
}
