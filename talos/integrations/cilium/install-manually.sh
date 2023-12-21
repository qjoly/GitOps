helm install \
    cilium \
    cilium/cilium \
    --version 1.60.0 \
    --namespace kube-system \
    --set ipam.mode=kubernetes \
    --set=kubeProxyReplacement=true \
    --set=securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --set=cgroup.autoMount.enabled=false \
    --set=cgroup.hostRoot=/sys/fs/cgroup \
    --set=k8sServiceHost=localhost \
    --set=k8sServicePort=7445 \
    --set=l2announcements.enabled=true \
    --set=k8sClientRateLimit.qps=32 \
    --set=k8sClientRateLimit.burst=5 \
    --set=l2announcements.leaseDuration="24h" \
    --set=l2announcements.leaseRenewDeadline="60s" \
    --set=l2announcements.leaseRetryPeriod="10s" \
    --set=externalIPs.enabled=true \
    --set=hubble.relay.enabled=true \
    --set=hubble.ui.enabled=true
    
