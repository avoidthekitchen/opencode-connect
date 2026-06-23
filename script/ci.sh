#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

run_step() {
  local name="$1"
  shift

  echo "::group::$name"
  if "$@"; then
    echo "::endgroup::"
  else
    local status=$?
    echo "::error::$name failed with exit code $status"
    echo "::endgroup::"
    return "$status"
  fi
}

run_step "Swift package tests" \
  swift test --package-path "$ROOT_DIR" --parallel --num-workers 1
run_step "Release packaging verification" \
  "$ROOT_DIR/script/test_release.sh"
