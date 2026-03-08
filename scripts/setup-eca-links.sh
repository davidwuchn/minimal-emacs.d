#!/usr/bin/env bash

set -euo pipefail

ECA_CONFIG_DIR="${HOME}/.config/eca"
EMACS_ECA_LINK="${HOME}/.emacs.d/eca"
BIN_DIR="${HOME}/bin"
BIN_ECA_LINK="${BIN_DIR}/eca"
ECA_SECURE_TARGET="${EMACS_ECA_LINK}/eca-secure"

mkdir -p "${HOME}/.emacs.d" "${BIN_DIR}"

if [[ ! -e "${ECA_CONFIG_DIR}" ]]; then
  echo "warning: ${ECA_CONFIG_DIR} does not exist yet"
fi

ln -sfn "${ECA_CONFIG_DIR}" "${EMACS_ECA_LINK}"

if [[ ! -e "${ECA_SECURE_TARGET}" ]]; then
  echo "warning: ${ECA_SECURE_TARGET} does not exist yet"
fi

ln -sfn "${ECA_SECURE_TARGET}" "${BIN_ECA_LINK}"

echo "ECA links configured:"
echo "  ${EMACS_ECA_LINK} -> $(readlink "${EMACS_ECA_LINK}" || true)"
echo "  ${BIN_ECA_LINK} -> $(readlink "${BIN_ECA_LINK}" || true)"
