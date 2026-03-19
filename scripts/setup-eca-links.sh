#!/usr/bin/env bash

set -euo pipefail

EMACS_DIR="${HOME}/.emacs.d"
EMACS_ECA_DIR="${EMACS_DIR}/eca"
VAR_ECA_DIR="${EMACS_DIR}/var/eca"
VAR_ECA_BINARY="${VAR_ECA_DIR}/eca"
EMACS_ECA_BINARY="${EMACS_ECA_DIR}/eca"
CONFIG_ECA_LINK="${HOME}/.config/eca"
BIN_DIR="${HOME}/bin"
BIN_ECA_LINK="${BIN_DIR}/eca"
ECA_SECURE_TARGET="${EMACS_ECA_DIR}/eca-secure"

mkdir -p "${EMACS_DIR}" "${VAR_ECA_DIR}" "${HOME}/.config" "${BIN_DIR}"

if [[ ! -d "${EMACS_ECA_DIR}" ]]; then
  echo "warning: ${EMACS_ECA_DIR} does not exist yet"
fi

ln -sfn "${EMACS_ECA_DIR}" "${CONFIG_ECA_LINK}"

if [[ -f "${VAR_ECA_BINARY}" ]]; then
  ln -sfn "${VAR_ECA_BINARY}" "${EMACS_ECA_BINARY}"
  echo "Linked: ${EMACS_ECA_BINARY} -> ${VAR_ECA_BINARY}"
else
  echo "warning: ${VAR_ECA_BINARY} does not exist yet (download with: eca upgrade or C-c a u)"
fi

if [[ ! -e "${ECA_SECURE_TARGET}" ]]; then
  echo "warning: ${ECA_SECURE_TARGET} does not exist yet"
fi

ln -sfn "${ECA_SECURE_TARGET}" "${BIN_ECA_LINK}"

echo ""
echo "ECA links configured:"
echo "  ${CONFIG_ECA_LINK} -> $(readlink "${CONFIG_ECA_LINK}" || true)"
echo "  ${EMACS_ECA_BINARY} -> $(readlink "${EMACS_ECA_BINARY}" 2>/dev/null || echo "not set")"
echo "  ${BIN_ECA_LINK} -> $(readlink "${BIN_ECA_LINK}" || true)"
