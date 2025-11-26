# Remove cert-manager
oc delete deployment -n cert-manager -l app.kubernetes.io/instance=cert-manager
oc patch certmanagers.operator cluster --type=merge -p='{"metadata":{"finalizers":null}}'
oc delete crd -l app.kubernetes.io/instance=cert-manager
oc delete crd certmanagers.operator.openshift.io
oc delete namespace cert-manager

# Remove job-set
oc delete --ignore-not-found deployment -n openshift-jobset-operator -l operators.coreos.com/job-set.openshift-jobset-operator
# This line needs to be revisited once job set is included for trainerv2 and we know the instance name
oc patch jobsetoperator cluster --type=merge -p='{"metadata":{"finalizers":null}}'
oc delete --ignore-not-found crd jobsetoperator
oc delete --ignore-not-found namespace openshift-jobset-operator
