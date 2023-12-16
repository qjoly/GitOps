cilium install \
    --version "v1.15.0-pre.3" \
    --set l2announcements.enabled=true \
    --set l2announcements.leaseDuration="300s" \
    --set l2announcements.leaseRenewDeadline="60s" \
    --set l2announcements.leaseRetryPeriod="10s" \
    --helm-set=ipam.mode=kubernetes \
    --helm-set=kubeProxyReplacement=true \
    --helm-set=securityContext.capabilities.ciliumAgent="{CHOWN,KILL,NET_ADMIN,NET_RAW,IPC_LOCK,SYS_ADMIN,SYS_RESOURCE,DAC_OVERRIDE,FOWNER,SETGID,SETUID}" \
    --helm-set=securityContext.capabilities.cleanCiliumState="{NET_ADMIN,SYS_ADMIN,SYS_RESOURCE}" \
    --helm-set=cgroup.autoMount.enabled=false \
    --helm-set=cgroup.hostRoot=/sys/fs/cgroup \
    --helm-set=k8sServiceHost=localhost \
    --helm-set=k8sServicePort=7445 \
    --helm-set=hubble.relay.enabled=true \
    --helm-set=hubble.ui.enabled=true \
    --helm-set=externalIPs.enabled= true \
    --helm-set=k8sClientRateLimit.qps=50 \
    --helm-set=k8sClientRateLimit.burst=100
