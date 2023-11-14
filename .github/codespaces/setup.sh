K9S_VERSION="v0.28.2"
SOPS_VERSION="v3.8.1"
AGE_VERSION="v1.1.1"
curl -LO https://github.com/getsops/sops/releases/download/$SOPS_VERSION/sops-$SOPS_VERSION.linux.amd64
sudo mv sops-$SOPS_VERSION.linux.amd64 /usr/local/bin/sops
chmod +x /usr/local/bin/sops

cd $(mktemp -d)
wget https://github.com/FiloSottile/age/releases/download/$AGE_VERSION/age-$AGE_VERSION-linux-amd64.tar.gz
tar xfz age-$AGE_VERSION-linux-amd64.tar.gz
chmod +x age/age*
sudo mv age/age* /usr/local/bin/
cd -


[ $(uname -m) = x86_64 ] && curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
chmod +x ./kind
sudo mv ./kind /usr/local/bin/kind

curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
mv kubectl /home/codespace/.local/bin/
kind create cluster

curl -s https://fluxcd.io/install.sh | sudo bash -- 
sudo chmod +x /usr/local/bin/flux
. <(flux completion bash)
flux install

cd $(mktemp -d)
wget https://github.com/derailed/k9s/releases/download/$K9S_VERSION/k9s_Linux_amd64.tar.gz 
tar xfz k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/k9s
cd - 

sh -c "$(curl --location https://taskfile.dev/install.sh)" -- -d -b ~/.local/bin

cp ~/.kube/config ./kubeconfig.yml