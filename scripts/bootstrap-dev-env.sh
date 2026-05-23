#!/usr/bin/env bash
# Clone ESP-IDF, esp-csi, and RuView next to this repo, then apply esp-csi patches.
# Intended for a fresh machine: clone this repository first, then run this script.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "${REPO_ROOT}"

IDF_DIR="${REPO_ROOT}/esp-idf-v6.0.1"
CSI_DIR="${REPO_ROOT}/esp-csi"
RUVIEW_DIR="${REPO_ROOT}/RuView"

# Must match patches/README.md and scripts/apply-esp-csi-patches.sh
ESP_CSI_PIN="8633d67152db2808f141cc1595970aa9cf406045"
IDF_TAG="v6.0.1"

usage() {
  echo "Usage: $0 [--skip-ruview]" >&2
  echo "  Clones missing dependencies under ${REPO_ROOT} and runs apply-esp-csi-patches.sh." >&2
  echo "  Existing git checkouts at the default paths are left unchanged (skipped)." >&2
  echo "  --skip-ruview  do not clone RuView (optional; LT の ESP32 手順だけなら省略可)" >&2
  echo "  Env: BOOTSTRAP_SKIP_IDF=1  skip ESP-IDF clone (for debugging)" >&2
}

skip_ruview=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-ruview) skip_ruview=true ;;
    -h | --help) usage; exit 0 ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 2
      ;;
  esac
  shift
done

require_empty_or_absent_or_git_repo() {
  local dir="$1"
  local label="$2"
  if [[ -e "${dir}/.git" ]]; then
    return 0
  fi
  if [[ -d "${dir}" ]] && [[ -n "$(ls -A "${dir}" 2>/dev/null || true)" ]]; then
    echo "error: ${label} path exists but is not a git repo: ${dir}" >&2
    echo "  Move or remove it, then re-run." >&2
    exit 1
  fi
  return 0
}

clone_idf() {
  if [[ "${BOOTSTRAP_SKIP_IDF:-}" == "1" ]]; then
    echo "Skip esp-idf (BOOTSTRAP_SKIP_IDF=1)."
    return 0
  fi
  if [[ -e "${IDF_DIR}/.git" ]]; then
    echo "Skip esp-idf: already present at ${IDF_DIR}"
    return 0
  fi
  require_empty_or_absent_or_git_repo "${IDF_DIR}" "esp-idf"
  rm -rf "${IDF_DIR}"
  echo "Cloning ESP-IDF ${IDF_TAG} (recursive; 数分〜かかります) ..."
  git clone -b "${IDF_TAG}" --recursive https://github.com/espressif/esp-idf.git "${IDF_DIR}"
}

clone_csi() {
  if [[ -e "${CSI_DIR}/.git" ]]; then
    echo "Skip esp-csi: already present at ${CSI_DIR}"
    return 0
  fi
  require_empty_or_absent_or_git_repo "${CSI_DIR}" "esp-csi"
  rm -rf "${CSI_DIR}"
  echo "Cloning esp-csi @ ${ESP_CSI_PIN} ..."
  git clone https://github.com/espressif/esp-csi.git "${CSI_DIR}"
  git -C "${CSI_DIR}" checkout -q "${ESP_CSI_PIN}"
}

clone_ruview() {
  if [[ "${skip_ruview}" == true ]]; then
    echo "Skip RuView (--skip-ruview)."
    return 0
  fi
  if [[ -e "${RUVIEW_DIR}/.git" ]]; then
    echo "Skip RuView: already present at ${RUVIEW_DIR}"
    return 0
  fi
  require_empty_or_absent_or_git_repo "${RUVIEW_DIR}" "RuView"
  rm -rf "${RUVIEW_DIR}"
  echo "Cloning RuView (shallow) ..."
  git clone --depth 1 https://github.com/ruvnet/RuView.git "${RUVIEW_DIR}"
}

clone_idf
clone_csi
clone_ruview

ESP_CSI_DIR="${CSI_DIR}" "${REPO_ROOT}/scripts/apply-esp-csi-patches.sh"

if [[ -e "${IDF_DIR}/.git" ]]; then
  cat <<EOF

---- 次に手元で実行（初回のみ・時間がかかる）----
  cd ${IDF_DIR}
  ./install.sh esp32s3
  . ./export.sh

可視化ツール用の Python venv は README の「PC側で可視化ツール」を参照。
公式: Getting Started https://docs.espressif.com/projects/esp-idf/en/${IDF_TAG}/esp32/get-started/index.html
EOF
else
  cat <<EOF

---- ESP-IDF が未配置のとき ----
  BOOTSTRAP_SKIP_IDF を付けずにもう一度このスクリプトを実行するか、README の手動 clone に従って
  ${IDF_DIR} を用意してから、上記と同様に install.sh / export.sh を実行してください。
EOF
fi
