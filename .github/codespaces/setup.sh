K9S_VERSION="v0.28.2"

# For AMD64 / x86_64
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
tar xvfz k9s_Linux_amd64.tar.gz
sudo mv k9s /usr/local/bin/k9s
cd - 
