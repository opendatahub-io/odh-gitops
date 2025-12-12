# Helm Chart for ODH/RHOAI

## 1. Repository Structure

Helm chart added to existing odh-gitops/ repository:

```
odh-gitops/
├── # KUSTOMIZE (existing, unchanged)
├── kustomization.yaml
├── components/operators/...
├── dependencies/...
├── configurations/...
│
└── # HELM (new)
    chart/
    ├── Chart.yaml          # name: rhoai-dependencies
    ├── values.yaml
    ├── templates/
    │   ├── _helpers.tpl
    │   ├── _operator.tpl
    │   ├── dependencies/*.yaml
    │   └── components/*.yaml
    └── README.md
```

## 2. values.yaml API

```yaml
global:
  installationType: olm  # olm | manifest
  olm:
    installPlanApproval: Automatic
    source: redhat-operators
    sourceNamespace: openshift-marketplace
  labels: {}

components:
  kserve:
    enabled: true
  
  kueue:
    enabled: false
    config:
      frameworks:
        - Deployment
        - Pod
        - PyTorchJob
        - RayCluster
        - RayJob
        - StatefulSet
  
  aipipelines:
    enabled: false

# Tri-state: auto (install if required) | true (always) | false (never)
dependencies:
  certManager:
    enabled: auto
    olm:
      channel: stable-v1
  
  leaderWorkerSet:
    enabled: auto
    olm:
      channel: stable-v1
  
  jobSet:
    enabled: auto
    olm:
      channel: stable-v1
  
  rhcl:
    enabled: auto
    olm:
      channel: stable-v1
    config:
      tls:
        enabled: false
  
  kueue:
    enabled: auto
    olm:
      channel: stable-v1
  
  clusterObservability:
    enabled: false
    olm:
      channel: stable
  
  opentelemetry:
    enabled: false
    olm:
      channel: stable
  
  tempo:
    enabled: false
    olm:
      channel: stable
  
  customMetricsAutoscaler:
    enabled: false
    olm:
      channel: stable
```

## 3. OLM / Manifest Support

Per-dependency override possible:

```yaml
global:
  installationType: olm

dependencies:
  certManager:
    installationType: manifest  # Override for this one
    manifest:
      version: "1.14.0"
```

## 4. CRD Ordering (Multi-Apply)

CRs use `lookup` - skipped if CRD missing:

```yaml
{{- if lookup "apiextensions.k8s.io/v1" "CustomResourceDefinition" "" "kueues.kueue.openshift.io" }}
apiVersion: kueue.openshift.io/v1
kind: Kueue
{{- end }}
```

Idempotent install:

```bash
for i in {1..5}; do
  helm upgrade --install rhoai ./chart -n rhoai-system --create-namespace
  sleep 60
done
```

## 5. Effort Estimate

| Task                                  | Files | Effort       |
|:--------------------------------------|:-----:|:-------------|
| Chart base (Chart.yaml, values.yaml)  | 2     | 1-2 hours    |
| _helpers.tpl (dependency logic)       | 1     | 2-3 hours    |
| _operator.tpl (OLM templates)         | 1     | 1-2 hours    |
| 9 operator templates (dependencies/)  | 9     | 3-4 hours    |
| Component configs (kueue, rhcl, etc.) | 4-5   | 2-3 hours    |
| README documentation                  | 1     | 1 hour       |
| Testing and debugging                 | -     | 2-3 hours    |
| **Total**                             | ~18   | 12-18 hours  |

Future work (not in scope):

| Task                                   | Effort                  |
|:---------------------------------------|:------------------------|
| Non-OLM manifest templates             | +4-8 hours per operator |
| Additional components (aipipelines)    | +2-3 hours each         |

## 6. Dependency Map

```
kserve      → [certManager, leaderWorkerSet, jobSet, rhcl]
kueue       → [kueue]
aipipelines → [TBD]
```
