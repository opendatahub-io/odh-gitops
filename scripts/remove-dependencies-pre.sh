# Remove keda CR
oc delete --ignore-not-found kedacontroller keda -n openshift-keda
