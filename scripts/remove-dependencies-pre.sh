# Remove keda CR
oc delete --ignore-not-found kedacontroller keda -n openshift-keda

# Remove NFD CR
oc delete --ignore-not-found nodefeaturediscovery nfd-instance -n openshift-nfd

# Remove GPU operator ClusterPolicy CR
oc delete --ignore-not-found clusterpolicy gpu-cluster-policy
