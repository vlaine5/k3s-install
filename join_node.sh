#!/bin/bash
set -e

K3S_VERSION="v1.31.6+k3s1"
MASTER_IP="192.168.1.100" # L'IP du nœud maître existant
TOKEN="<TON_TOKEN>"       # Le token copié depuis /var/lib/rancher/k3s/server/node-token

# ------------------------------------------------------------
# Check si c'est un control-plane ou un worker
# usage: ./join_node.sh [server|agent]
# ------------------------------------------------------------

echo "Vérification de la présence d'une ancienne installation K3s..."
if systemctl is-active --quiet k3s; then
  echo "  ➜ K3s est déjà installé et actif, on le supprime..."
  if [ -f /usr/local/bin/k3s-uninstall.sh ]; then
    /usr/local/bin/k3s-uninstall.sh
  else
    systemctl stop k3s || true
    systemctl disable k3s || true
    rm -f /etc/systemd/system/k3s.service
    rm -f /usr/local/bin/k3s
    rm -f /usr/local/bin/kubectl
    rm -f /usr/local/bin/crictl
    rm -f /usr/local/bin/k3s-killall.sh
    rm -f /usr/local/bin/k3s-uninstall.sh
  fi
fi

echo "  ➜ Suppression des anciens dossiers K3s..."
sudo rm -rf /var/lib/rancher/k3s
sudo rm -rf /etc/rancher/k3s
ROLE="$1"

if [ "$ROLE" != "server" ] && [ "$ROLE" != "agent" ]; then
  echo "Usage: $0 <server|agent>"
  exit 1
fi


echo "Mise à jour du système et installation des dépendances..."
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl iptables jq conntrack socat

echo "Chargement des modules noyau requis..."
sudo modprobe br_netfilter
sudo modprobe overlay

cat <<EOF | sudo tee /etc/modules-load.d/k3s.conf
br_netfilter
overlay
EOF

if [ "$ROLE" = "server" ]; then
  echo "Installation de K3s en tant que Control Plane"
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION \
    K3S_URL="https://$MASTER_IP:6443" \
    K3S_TOKEN="$TOKEN" \
     sh -s - server --server "https://$MASTER_IP:6443" \
      --disable servicelb \
     --flannel-backend=host-gw \
     --tls-san=$(hostname -I | awk '{print $1}')
   
else
  echo "Installation de K3s en tant que Worker Node"
  curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=$K3S_VERSION \
    K3S_URL="https://$MASTER_IP:6443" \
    K3S_TOKEN="$TOKEN" \
    sh -s - agent
   
fi

echo "Nœud [$ROLE] rejoint le cluster avec succès !"
kubectl get nodes -o wide
