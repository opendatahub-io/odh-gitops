# Remove cert-manager
oc delete --ignore-not-found deployment -n cert-manager -l app.kubernetes.io/instance=cert-manager
oc patch certmanagers.operator cluster --type=merge -p='{"metadata":{"finalizers":null}}'
oc delete --ignore-not-found crd -l app.kubernetes.io/instance=cert-manager
oc delete --ignore-not-found crd certmanagers.operator.openshift.io
oc delete --ignore-not-found namespace cert-manager

# Remove job-set
oc delete --ignore-not-found deployment -n openshift-jobset-operator -l operators.coreos.com/job-set.openshift-jobset-operator
oc delete --ignore-not-found crd jobsetoperators.operator.openshift.io
oc delete --ignore-not-found namespace openshift-jobset-operator

# Remove kueue
oc delete --ignore-not-found crd kueues.kueue.openshift.io clusterqueues.kueue.x-k8s.io resourceflavors.kueue.x-k8s.io

# Remove keda CRD
oc delete --ignore-not-found crd clustertriggerauthentications.keda.sh kedacontrollers.keda.sh scaledjobs.keda.sh scaledobjects.keda.sh triggerauthentications.keda.sh cloudeventsources.eventing.keda.sh clustercloudeventsources.eventing.keda.sh

# Remove leader-worker-set CRD
oc delete --ignore-not-found crd leaderworkersetoperators.operator.openshift.io

# Remove kuadrant CRD
oc delete --ignore-not-found crd authorinos.operator.authorino.kuadrant.io authconfigs.authorino.kuadrant.io
oc delete --ignore-not-found crd kuadrants.kuadrant.io
oc delete --ignore-not-found crd authpolicies.kuadrant.io dnshealthcheckprobes.kuadrant.io dnspolicies.kuadrant.io dnsrecords.kuadrant.io limitadors.limitador.kuadrant.io oidcpolicies.extensions.kuadrant.io planpolicies.extensions.kuadrant.io ratelimitpolicies.kuadrant.io telemetrypolicies.extensions.kuadrant.io tlspolicies.kuadrant.io tokenratelimitpolicies.kuadrant.io

# Remove NFD
oc delete --ignore-not-found subscription -n openshift-nfd nfd
oc delete --ignore-not-found deployment -n openshift-nfd -l operators.coreos.com/nfd.openshift-nfd
oc delete --ignore-not-found crd nodefeaturediscoveries.nfd.openshift.io nodefeaturerules.nfd.k8s-sigs.io nodefeatures.nfd.k8s-sigs.io nodefeaturegroups.nfd.k8s-sigs.io noderesourcetopologies.topology.node.k8s.io
oc delete --ignore-not-found namespace openshift-nfd

# Remove GPU operator
oc delete --ignore-not-found subscription -n nvidia-gpu-operator gpu-operator-certified
oc delete --ignore-not-found deployment -n nvidia-gpu-operator -l operators.coreos.com/gpu-operator-certified.nvidia-gpu-operator
oc delete --ignore-not-found crd clusterpolicies.nvidia.com nvidiadrivers.nvidia.com
oc delete --ignore-not-found namespace nvidia-gpu-operator
