generate:
	helm repo add argocd https://argoproj.github.io/argo-helm
	helm template -n argocd argocd --create-namespace argocd/argo-cd -f values.yaml > argocd.install.yaml
