#!/usr/bin/env bash

set -euo pipefail

expected_host="beta.online-go.com"
expected_root="https://${expected_host}"
expected_usernames="hakhoa,hakhoa2,hakhoa3,hakhoa4"

if [[ "${OGS_BETA_HOST:-}" != "$expected_root" ]]; then
  echo "Refusing to run: OGS_BETA_HOST must be exactly ${expected_root}." >&2
  exit 64
fi

if [[ "${OGS_BETA_USERNAMES:-}" != "$expected_usernames" ]]; then
  echo "Refusing to run: OGS_BETA_USERNAMES must contain only the dedicated beta accounts." >&2
  exit 64
fi

if [[ -z "${OGS_BETA_PASSWORD:-}" ]]; then
  echo "OGS_BETA_PASSWORD is not configured." >&2
  exit 64
fi

echo "Validated the isolated OGS beta environment for four dedicated test accounts."
