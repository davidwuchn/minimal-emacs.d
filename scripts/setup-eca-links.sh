#!/usr/bin/env bash

set -euo pipefail

EMACS_DIR="${HOME}/.emacs.d"
EMACS_ECA_DIR="${EMACS_DIR}/eca"
VAR_ECA_DIR="${EMACS_DIR}/var/eca"
CONFIG_ECA_LINK="${HOME}/.config/eca"
BIN_DIR="${HOME}/bin"
BIN_ECA_LINK="${BIN_DIR}/eca"
ECA_SECURE_TARGET="${EMACS_ECA_DIR}/eca-secure"

mkdir -p "${EMACS_DIR}" "${VAR_ECA_DIR}" "${HOME}/.config" "${BIN_DIR}"

if [[ ! -d "${EMACS_ECA_DIR}" ]]; then
  echo "warning: ${EMACS_ECA_DIR} does not exist yet"
fi

ln -sfn "${EMACS_ECA_DIR}" "${CONFIG_ECA_LINK}"

if [[ ! -e "${ECA_SECURE_TARGET}" ]]; then
  echo "warning: ${ECA_SECURE_TARGET} does not exist yet"
fi

ln -sfn "${ECA_SECURE_TARGET}" "${BIN_ECA_LINK}"

echo "ECA links configured:"
echo "  ${CONFIG_ECA_LINK} -> $(readlink "${CONFIG_ECA_LINK}" || true)"
echo "  ${BIN_ECA_LINK} -> $(readlink "${BIN_ECA_LINK}" || true)"
echo "  ECA binary: ${VAR_ECA_DIR}/eca (downloaded by ai-code)"
