#!/usr/bin/env bash

set -euo pipefail

# Canonical paths (following ~/.emacs.d as source of truth)
EMACS_ECA_DIR="${HOME}/.emacs.d/eca"
CONFIG_ECA_LINK="${HOME}/.config/eca"
BIN_DIR="${HOME}/bin"
BIN_ECA_LINK="${BIN_DIR}/eca"
ECA_SECURE_TARGET="${EMACS_ECA_DIR}/eca-secure"
BEHAVIORS_DIR="${EMACS_ECA_DIR}/behaviors"
HOOKS_DIR="${EMACS_ECA_DIR}/hooks"

mkdir -p "${HOME}/.emacs.d" "${HOME}/.config" "${BIN_DIR}"

if [[ ! -d "${EMACS_ECA_DIR}" ]]; then
  echo "warning: ${EMACS_ECA_DIR} does not exist yet"
fi

ln -sfn "${EMACS_ECA_DIR}" "${CONFIG_ECA_LINK}"

if [[ ! -e "${ECA_SECURE_TARGET}" ]]; then
  echo "warning: ${ECA_SECURE_TARGET} does not exist yet"
fi

ln -sfn "${ECA_SECURE_TARGET}" "${BIN_ECA_LINK}"

# Verify behaviors system
if [[ ! -d "${BEHAVIORS_DIR}" ]]; then
  echo "warning: ${BEHAVIORS_DIR} does not exist (behaviors system not installed)"
fi

if [[ ! -d "${HOOKS_DIR}" ]]; then
  echo "warning: ${HOOKS_DIR} does not exist (ECA hooks not installed)"
fi

echo "ECA links configured:"
echo "  ${CONFIG_ECA_LINK} -> $(readlink "${CONFIG_ECA_LINK}" || true)"
echo "  ${BIN_ECA_LINK} -> $(readlink "${BIN_ECA_LINK}" || true)"
echo ""
echo "Behaviors system:"
echo "  behaviors: ${BEHAVIORS_DIR} $(test -d "${BEHAVIORS_DIR}" && echo '✓' || echo '✗')"
echo "  hooks:     ${HOOKS_DIR} $(test -d "${HOOKS_DIR}" && echo '✓' || echo '✗')"
