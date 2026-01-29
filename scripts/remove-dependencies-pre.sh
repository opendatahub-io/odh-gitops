# Remove keda CR
oc delete --ignore-not-found kedacontroller keda -n openshift-keda

# Remove NFD CR
if oc get crd nodefeaturediscoveries.nfd.openshift.io &>/dev/null; then
  oc delete --ignore-not-found nodefeaturediscovery nfd-instance -n openshift-nfd
fi

# Remove GPU operator ClusterPolicy CR
if oc get crd clusterpolicies.nvidia.com &>/dev/null; then
  oc delete --ignore-not-found clusterpolicy gpu-cluster-policy
fi
