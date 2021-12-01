#/bin/bash
set -euo pipefail

# Generate input file for cloud-init.
cat << EOF > cloud-init.txt
#cloud-config
package_upgrade: true
packages:
  - curl
output: {all: '| tee -a /var/log/cloud-init-output.log'}
runcmd:
  - curl https://releases.rancher.com/install-docker/18.09.sh | sh
  - sudo usermod -aG docker adminuser
  - curl -sfL https://get.k3s.io | sh -s - server --tls-san demo-37yjin46oafey.westeurope.cloudapp.azure.com
  - sudo ufw allow 6443/tcp
  - sudo ufw allow 443/tcp
  - sudo cp /var/lib/rancher/k3s/server/node-token .
  - sudo chown adminuser:adminuser node-token
  - sudo sed 's/127.0.0.1/demo-37yjin46oafey.westeurope.cloudapp.azure.com/g' /etc/rancher/k3s/k3s.yaml > k3s-config
  - chmod 600 k3s-config
  - wget https://get.helm.sh/helm-v3.7.1-linux-amd64.tar.gz  
  - tar -xvf helm-v3.7.1-linux-amd64.tar.gz 
  - sudo mv linux-amd64/helm /usr/local/bin/helm
  - helm repo add stable https://charts.helm.sh/stable
  - helm repo update
  - helm repo add argo https://argoproj.github.io/argo-helm
  - mkdir -p .kube
  - sudo cp /etc/rancher/k3s/k3s.yaml ./.kube/config
  - sudo chown -R adminuser:adminuser ./.kube
  - sudo kubectl create ns argocd
  - helm upgrade --install demo-argo-cd argo/argo-cd --version 3.26.12 -n argocd
EOF
