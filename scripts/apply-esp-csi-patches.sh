#!/usr/bin/env bash
# Apply esp-csi patches for ESP-IDF v6 compatibility (this LT repo).
# Run from anywhere after esp-csi is cloned (e.g. scripts/bootstrap-dev-env.sh).
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Override if esp-csi lives elsewhere (e.g. manual clone without this superproject layout).
ESP_CSI_DIR="${ESP_CSI_DIR:-${REPO_ROOT}/esp-csi}"
PATCH_DIR="${REPO_ROOT}/patches/esp-csi"

# Commit the patch series was generated from (see patches/README.md).
EXPECTED_ESP_CSI_COMMIT="8633d67152db2808f141cc1595970aa9cf406045"

usage() {
  echo "Usage: $0 [--force]" >&2
  echo "  Applies all ${PATCH_DIR}/*.patch inside esp-csi." >&2
  echo "  --force  apply even if esp-csi HEAD does not match the expected commit" >&2
  echo "  ESP_CSI_DIR  optional env; default is <repo>/esp-csi" >&2
}

force=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) force=true ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

if [[ ! -e "${ESP_CSI_DIR}/.git" ]]; then
  echo "error: esp-csi git metadata not found at ${ESP_CSI_DIR}/.git" >&2
  echo "  Initialize deps: ./scripts/bootstrap-dev-env.sh" >&2
  exit 1
fi

if [[ ! -d "${PATCH_DIR}" ]]; then
  echo "error: patch directory missing: ${PATCH_DIR}" >&2
  exit 1
fi

mapfile -t patches < <(find "${PATCH_DIR}" -maxdepth 1 -name '*.patch' -type f | LC_ALL=C sort)
if [[ "${#patches[@]}" -eq 0 ]]; then
  echo "error: no *.patch files in ${PATCH_DIR}" >&2
  exit 1
fi

actual="$(git -C "${ESP_CSI_DIR}" rev-parse HEAD)"
if [[ "${actual}" != "${EXPECTED_ESP_CSI_COMMIT}" ]]; then
  echo "warning: esp-csi HEAD is ${actual}" >&2
  echo "         expected ${EXPECTED_ESP_CSI_COMMIT} (regenerate patches if esp-csi was bumped)." >&2
  if [[ "${force}" != true ]]; then
    echo "Refusing to apply. Re-run with --force if you know the patch still applies." >&2
    exit 1
  fi
fi

for p in "${patches[@]}"; do
  base="$(basename "${p}")"
  if git -C "${ESP_CSI_DIR}" apply --reverse --check "${p}" &>/dev/null; then
    echo "Skip ${base} (already applied)."
    continue
  fi
  echo "Applying ${base} ..."
  git -C "${ESP_CSI_DIR}" apply --whitespace=warn "${p}"
done

echo "Done. esp-csi is patched for ESP-IDF v6 (working tree modified)."
