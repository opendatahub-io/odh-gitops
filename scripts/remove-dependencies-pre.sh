# Remove keda CR
if oc get crd kedacontrollers.keda.sh &>/dev/null; then
  oc delete --ignore-not-found kedacontroller keda -n openshift-keda
fi

# Remove NFD CR
if oc get crd nodefeaturediscoveries.nfd.openshift.io &>/dev/null; then
  oc delete --ignore-not-found nodefeaturediscovery nfd-instance -n openshift-nfd
fi

# Remove GPU operator ClusterPolicy CR
if oc get crd clusterpolicies.nvidia.com &>/dev/null; then
  oc delete --ignore-not-found clusterpolicy gpu-cluster-policy
fi

# Remove Kueue CR (force-remove finalizer if the operator hangs on graceful delete)
if oc get crd kueues.kueue.openshift.io &>/dev/null; then
  oc delete --ignore-not-found --timeout=30s kueue.kueue.openshift.io cluster || \
    oc patch kueue.kueue.openshift.io cluster --type=merge -p '{"metadata":{"finalizers":null}}'
fi
