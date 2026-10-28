#!/usr/bin/env bash
# Genera los manifiestos finales de un entorno con la imagen EXACTA del commit
# y la anotacion de trazabilidad (kubernetes.io/change-cause). Escribe el YAML en stdout.
#
# Uso: scripts/render-manifests.sh <staging|production> <imagen> <tag> [change-cause]
# Ej.: scripts/render-manifests.sh production ghcr.io/chelo11/ms-vehiculos 3f2a9c1... "commit 3f2a9c1"
set -euo pipefail

ENTORNO="${1:?Uso: render-manifests.sh <staging|production> <imagen> <tag> [change-cause]}"
IMAGEN="${2:?Falta la imagen}"
TAG="${3:?Falta el tag}"
# Solo caracteres seguros: el valor termina dentro de un YAML y de una expresion sed
CAUSA="$(printf '%s' "${4:-commit ${TAG}}" | tr -cd '[:alnum:] ._:/(),-')"

RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cp -r "$RAIZ/k8s" "$TMP/"
OVERLAY="$TMP/k8s/overlays/$ENTORNO"
[[ -f "$OVERLAY/kustomization.yaml" ]] || { echo "Entorno desconocido: $ENTORNO" >&2; exit 1; }

# Se trabaja sobre una copia: el repositorio nunca queda modificado
sed -i -E \
  -e "s|^([[:space:]]*newName:).*|\1 ${IMAGEN}|" \
  -e "s|^([[:space:]]*newTag:).*|\1 \"${TAG}\"|" \
  "$OVERLAY/kustomization.yaml"

kubectl kustomize "$OVERLAY" \
  | sed -E "s|^([[:space:]]*kubernetes\.io/change-cause:).*|\1 \"${CAUSA}\"|"
