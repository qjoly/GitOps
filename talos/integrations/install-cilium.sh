cilium install \
    --helm-set=ipam.mode=kubernetes \
    --helm-set=kubeProxyReplacement=true \
    --helm-set=securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --helm-set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --helm-set=cgroup.autoMount.enabled=false \
    --helm-set=cgroup.hostRoot=/sys/fs/cgroup \
    --helm-set=k8sServiceHost=localhost \
    --helm-set=k8sServicePort=7445 \
    --helm-set=hubble.relay.enabled=true \
    --helm-set=hubble.ui.enabled=true



#helm install cilium cilium/cilium --version 1.14.3 \
#	--namespace kube-system \
#	--set kubeProxyReplacement=true \
#	--set k8sServiceHost=172.16.66.99 \
#	--set k8sServicePort=6443 \
#	--set hubble.relay.enabled=true \
#	--set hubble.ui.enabled=true \
#	--set hubble.peerService.clusterDomain=cluster \
#	--set operator.replicas=1 \
#	--set localRedirectPolicy=true \
#	--set bpf.masquerade=true \
#	--set bgpControlPlane.enabled=true \
#	--set ipam.operator.clusterPoolIPv4PodCIDRList='10.66.0.0/16' \
#	--set ipam.operator.clusterPoolIPv4MaskSize=18 \
#	--set ingressController.enabled=true \
#	--set ingressController.loadbalancerMode=shared \
#	--set envoy.enabled=true
