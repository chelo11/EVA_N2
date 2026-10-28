#!/usr/bin/env bash
# Se ejecuta EN la instancia EC2: lo invoca por SSH el job de produccion del pipeline.
# Importa la imagen, aplica los manifiestos y espera el rollout. Si el rollout
# falla, revierte automaticamente a la revision anterior (si existe).
#
# Uso: deploy-k3s.sh <directorio con image.tar y production.yaml>
set -euo pipefail

DIR="${1:?Uso: deploy-k3s.sh <directorio>}"
NS="vehiculos"
kc() { sudo k3s kubectl "$@"; }

diagnostico() {
  kc -n "$NS" get pods,pvc -o wide || true
  kc -n "$NS" get events --sort-by=.lastTimestamp | tail -25 || true
  kc -n "$NS" describe pod mysql-0 | tail -25 || true
  kc -n "$NS" logs mysql-0 --tail=60 || true
  kc -n "$NS" logs deployment/ms-vehiculos --all-containers --tail=80 || true
}

kc get nodes >/dev/null 2>&1 \
  || { echo "::error::k3s no esta disponible en la instancia. Ejecuta infra/setup-ec2.sh"; exit 1; }
kc -n "$NS" get secret mysql-credentials >/dev/null 2>&1 \
  || { echo "::error::Falta el Secret mysql-credentials en el namespace $NS (lo crea infra/setup-ec2.sh)"; exit 1; }

echo "▶ Importando la imagen en el containerd de k3s..."
sudo k3s ctr -n k8s.io images import "$DIR/image.tar"
rm -f "$DIR/image.tar"

echo "▶ Aplicando manifiestos..."
kc -n "$NS" apply -f "$DIR/production.yaml"

echo "▶ Esperando a MySQL..."
if ! kc -n "$NS" rollout status statefulset/mysql --timeout=300s; then
  echo "::error::MySQL no quedo listo"
  diagnostico
  exit 1
fi

echo "▶ Esperando el rollout de la API..."
if ! kc -n "$NS" rollout status deployment/ms-vehiculos --timeout=420s; then
  echo "::error::El rollout de la API fallo"
  diagnostico
  REV=$(kc -n "$NS" get deploy ms-vehiculos -o jsonpath='{.metadata.annotations.deployment\.kubernetes\.io/revision}')
  if [[ "${REV:-1}" -gt 1 ]]; then
    echo "▶ Revirtiendo a la revision anterior..."
    kc -n "$NS" rollout undo deployment/ms-vehiculos
    kc -n "$NS" rollout status deployment/ms-vehiculos --timeout=300s || true
  else
    echo "::warning::Primer despliegue: no hay una revision anterior a la que volver"
  fi
  exit 1
fi

echo "▶ Historial de revisiones (cada una indica el commit que la genero):"
kc -n "$NS" rollout history deployment/ms-vehiculos | tail -6
kc -n "$NS" get deployment,hpa,pods -o wide

rm -rf "$DIR"
