#!/usr/bin/env bash
# Prepara una instancia AWS EC2 (Ubuntu) como nodo k3s de PRODUCCION.
# Idempotente: se puede ejecutar varias veces sin romper nada.
#
# Uso (en la instancia):  bash setup-ec2.sh
# Requisitos recomendados: t3.medium (4 GB RAM), 20 GiB de disco, puertos 22 y 80 abiertos.
set -euo pipefail

K3S_VERSION="${K3S_VERSION:-v1.36.5+k3s1}"   # misma version menor que el cluster de staging (kind v1.36)
NS="vehiculos"
SWAP_GB="${SWAP_GB:-2}"
kc() { sudo k3s kubectl "$@"; }

echo "== 1/6 Expandir el disco raiz al tamano del volumen EBS"
# Al ampliar el volumen en AWS, la particion y el sistema de archivos no crecen solos.
ROOT_PART=$(lsblk -nro NAME,MOUNTPOINT | awk '$2 == "/" {print $1; exit}')
ROOT_DISK=$(lsblk -nro PKNAME "/dev/$ROOT_PART")
PART_NUM=$(cat "/sys/class/block/$ROOT_PART/partition")
sudo growpart "/dev/$ROOT_DISK" "$PART_NUM" || true   # "NOCHANGE" si ya ocupa todo el disco
case "$(findmnt -n -o FSTYPE /)" in
  ext4) sudo resize2fs "/dev/$ROOT_PART" ;;
  xfs)  sudo xfs_growfs / ;;
esac

echo "== 2/6 Recursos de la instancia"
MEM_MB=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo)
DISCO_GB=$(df -BG --output=avail / | tail -1 | tr -dc '0-9')
echo "RAM: ${MEM_MB} MB | Disco libre: ${DISCO_GB} GB"
if (( MEM_MB < 1800 )); then
  echo "⚠️  Menos de 2 GB de RAM: se recomienda t3.medium (4 GB) para k3s + MySQL + 2 replicas."
fi
if (( DISCO_GB < 6 )); then
  echo "❌ Menos de 6 GB libres: amplia el volumen EBS (20 GiB recomendado) antes de continuar."
  exit 1
fi

echo "== 3/6 Swap de ${SWAP_GB} GB (colchon ante picos de memoria)"
if ! swapon --show=NAME --noheadings | grep -qx '/swapfile'; then
  [[ -f /swapfile ]] || sudo fallocate -l "${SWAP_GB}G" /swapfile
  sudo chmod 600 /swapfile
  sudo mkswap /swapfile >/dev/null
  sudo swapon /swapfile
fi
grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab >/dev/null

echo "== 4/6 k3s ${K3S_VERSION}"
if ! command -v k3s >/dev/null 2>&1; then
  # --secrets-encryption: los Secrets quedan cifrados en reposo en la base de datos de k3s
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION="$K3S_VERSION" sh -s - server \
    --write-kubeconfig-mode 600 \
    --secrets-encryption
fi
for _ in $(seq 1 36); do
  kc get nodes 2>/dev/null | grep -q ' Ready' && break
  sleep 5
done
kc wait --for=condition=Ready node --all --timeout=60s

echo "== 5/6 Namespace ${NS}"
kc create namespace "$NS" --dry-run=client -o yaml | kc apply -f -

echo "== 6/6 Secret con las credenciales de MySQL (solo si no existe)"
if ! kc -n "$NS" get secret mysql-credentials >/dev/null 2>&1; then
  kc -n "$NS" create secret generic mysql-credentials \
    --from-literal=root-password="$(openssl rand -hex 24)" \
    --from-literal=username=vehiculos \
    --from-literal=password="$(openssl rand -hex 24)"
  echo "Secret creado con contrasenas aleatorias: nunca salen de la instancia ni quedan en GitHub."
else
  echo "El Secret ya existe: se conserva (la base de datos sigue usando esas credenciales)."
fi

kc get nodes -o wide
echo "✅ Instancia lista para recibir despliegues del pipeline."
