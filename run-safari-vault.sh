#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$(SAFARI_VAULT_ENVIRONMENT=development "$ROOT/scripts/build-app.sh" | tail -n 1)"
open -n "$APP"
