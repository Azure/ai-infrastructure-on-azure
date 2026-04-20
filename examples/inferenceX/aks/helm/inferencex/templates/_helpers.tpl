{{/*
Create a default fully qualified app name.
Truncate at 63 chars (DNS naming spec limit).
*/}}
{{- define "inferencex.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "inferencex.labels" -}}
app.kubernetes.io/name: inferencex
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Worker pod spec shared between prefill and decode MPIJobs.
Expects a dict with: role, gpus, fullname, root (top-level context)
*/}}
{{- define "inferencex.workerPodSpec" -}}
hostIPC: true
affinity:
  podAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
    - labelSelector:
        matchLabels:
          task: {{ .fullname }}-{{ .role }}
      topologyKey: {{ .root.Values.affinity.topologyKey }}
  nodeAffinity:
    requiredDuringSchedulingIgnoredDuringExecution:
      nodeSelectorTerms:
      - matchExpressions:
        - key: {{ .root.Values.affinity.nodePoolLabel }}
          operator: In
          values:
          - {{ .root.Values.affinity.nodePoolValue }}
        {{- if .root.Values.nodePinning.enabled }}
        {{- $nodes := index (index .root.Values.nodePinning .role) (int .workerIndex) }}
        - key: kubernetes.io/hostname
          operator: In
          values:
          {{- range $nodes }}
          - {{ . }}
          {{- end }}
        {{- end }}
tolerations:
- key: nvidia.com/gpu
  operator: Exists
  effect: NoSchedule
- key: sku
  operator: Equal
  value: gpu
  effect: NoSchedule
initContainers:
{{- if ne .root.Values.storage.type "pvc" }}
- name: download-model
  image: python:3.11-slim
  imagePullPolicy: IfNotPresent
  command:
  - bash
  - -c
  - |
    set -e
    MODEL_DIR="{{ .root.Values.model.mountPath }}/{{ .root.Values.model.localDir }}"
    if [ -f "${MODEL_DIR}/download-complete" ]; then
      echo "Model already downloaded, skipping"
      exit 0
    fi
    pip install -q huggingface_hub hf_transfer
    export HF_HUB_ENABLE_HF_TRANSFER=1
    {{- if .root.Values.model.hfTokenSecret }}
    export HF_TOKEN=$(cat /hf-token/token)
    {{- end }}
    MAX_RETRIES=5
    for attempt in $(seq 1 $MAX_RETRIES); do
      echo "Download attempt $attempt/$MAX_RETRIES"
      if hf download {{ .root.Values.model.id }} \
           --local-dir "${MODEL_DIR}"; then
        touch "${MODEL_DIR}/download-complete"
        echo "Download complete"
        exit 0
      fi
      echo "Attempt $attempt failed, retrying in 10s..."
      sleep 10
    done
    echo "All $MAX_RETRIES attempts failed"
    exit 1
  volumeMounts:
  - name: model-storage
    mountPath: {{ .root.Values.model.mountPath }}
  {{- if .root.Values.model.hfTokenSecret }}
  - name: hf-token
    mountPath: /hf-token
    readOnly: true
  {{- end }}
  resources:
    requests:
      cpu: "4"
      memory: 8Gi
    limits:
      cpu: "8"
      memory: 16Gi
{{- end }}
- name: gen-ssh-keys
  image: {{ .root.Values.image.runtime }}
  imagePullPolicy: {{ .root.Values.image.pullPolicy }}
  securityContext:
    runAsUser: 0
  command:
  - bash
  - -c
  - |
    cp -a /etc/ssh/* /ssh-overlay/
    yes | ssh-keygen -q -N "" -t rsa -f /ssh-overlay/ssh_host_rsa_key
    yes | ssh-keygen -q -N "" -t ecdsa -f /ssh-overlay/ssh_host_ecdsa_key
    yes | ssh-keygen -q -N "" -t ed25519 -f /ssh-overlay/ssh_host_ed25519_key
    # Allow root login and disable strict permission checking on /root/.ssh
    echo "PermitRootLogin yes" >> /ssh-overlay/sshd_config
    echo "StrictModes no" >> /ssh-overlay/sshd_config
    chmod 0755 /sshd-run
    chown root:root /sshd-run
    ls -la /ssh-overlay/ssh_host_*
  volumeMounts:
  - name: ssh-keys
    mountPath: /ssh-overlay
  - name: sshd-run
    mountPath: /sshd-run
containers:
- name: worker
  image: {{ .root.Values.image.runtime }}
  imagePullPolicy: {{ .root.Values.image.pullPolicy }}
  resources:
    requests:
      {{ .root.Values.gpuResource }}: {{ .gpus }}
      {{ .root.Values.rdmaResource }}: {{ .gpus }}
    limits:
      {{ .root.Values.gpuResource }}: {{ .gpus }}
      {{ .root.Values.rdmaResource }}: {{ .gpus }}
    {{- if .root.Values.dra.enabled }}
    claims:
    - name: {{ .root.Values.dra.claimTemplateName }}
    {{- end }}
  securityContext:
    privileged: true
    runAsUser: 0
    capabilities:
      add: ["IPC_LOCK"]
  volumeMounts:
  - name: shm
    mountPath: /dev/shm
  - name: model-storage
    mountPath: {{ .root.Values.model.mountPath }}
  - name: scripts
    mountPath: /scripts
    readOnly: true
  - name: engine-config
    mountPath: /engine-config
    readOnly: true
  - name: ssh-keys
    mountPath: /etc/ssh
  - name: sshd-run
    mountPath: /run/sshd
{{- if .root.Values.dra.enabled }}
resourceClaims:
- name: {{ .root.Values.dra.claimTemplateName }}
  resourceClaimTemplateName: {{ .root.Values.dra.claimTemplateName }}
{{- end }}
volumes:
- name: shm
  emptyDir:
    medium: Memory
- name: model-storage
{{- if eq .root.Values.storage.type "pvc" }}
  persistentVolumeClaim:
    claimName: {{ .fullname }}-model
    readOnly: true
{{- else if eq .root.Values.storage.type "hostPath" }}
  hostPath:
    path: {{ .root.Values.storage.hostPath }}
    type: DirectoryOrCreate
{{- else }}
  emptyDir:
    sizeLimit: {{ .root.Values.storage.size }}
{{- end }}
- name: scripts
  configMap:
    name: {{ .fullname }}-scripts
    defaultMode: 0755
- name: engine-config
  configMap:
    name: {{ .fullname }}-engine-config
- name: ssh-keys
  emptyDir: {}
- name: sshd-run
  emptyDir: {}
{{- if .root.Values.model.hfTokenSecret }}
- name: hf-token
  secret:
    secretName: {{ .root.Values.model.hfTokenSecret }}
{{- end }}
enableServiceLinks: false
automountServiceAccountToken: false
{{- end }}

{{/*
Launcher env vars common to all MPIJobs.
Expects root (top-level context) and role.
*/}}
{{- define "inferencex.launcherEnv" -}}
- name: WORKER_ROLE
  value: {{ .role | quote }}
- name: MODEL_HF_ID
  value: {{ .root.Values.model.id | quote }}
- name: MODEL_LOCAL_DIR
  value: "{{ .root.Values.model.mountPath }}/{{ .root.Values.model.localDir }}"
- name: MODEL_NAME
  value: {{ .root.Values.model.name | quote }}
- name: ETCD_ENDPOINTS
  value: "http://{{ .fullname }}-etcd:2379"
- name: NATS_SERVER
  value: "nats://{{ .fullname }}-nats:4222"
- name: DYN_REQUEST_PLANE
  value: "nats"
{{- if .root.Values.model.hfTokenSecret }}
- name: HF_TOKEN
  valueFrom:
    secretKeyRef:
      name: {{ .root.Values.model.hfTokenSecret }}
      key: token
{{- end }}
{{- range $key, $value := .root.Values.ncclEnv }}
- name: {{ $key }}
  value: "{{ $value }}"
{{- end }}
{{- if .root.Values.trtllmEnv }}
{{- range $key, $value := .root.Values.trtllmEnv.common }}
- name: {{ $key }}
  value: "{{ $value }}"
{{- end }}
{{- if eq .role "decode" }}
{{- range $key, $value := .root.Values.trtllmEnv.decode }}
- name: {{ $key }}
  value: "{{ $value }}"
{{- end }}
{{- end }}
{{- end }}
{{- end }}

{{/*
mpirun -x flags for forwarding env vars to workers.
*/}}
{{- define "inferencex.mpirunXFlags" -}}
-x LD_LIBRARY_PATH \
-x WORKER_ROLE \
-x MODEL_HF_ID \
-x MODEL_LOCAL_DIR \
-x MODEL_NAME \
-x ETCD_ENDPOINTS \
-x NATS_SERVER \
-x DYN_REQUEST_PLANE \
{{- if .root.Values.model.hfTokenSecret }}
-x HF_TOKEN \
{{- end }}
{{- range $key, $_ := .root.Values.ncclEnv }}
-x {{ $key }} \
{{- end }}
{{- if .root.Values.trtllmEnv }}
{{- range $key, $_ := .root.Values.trtllmEnv.common }}
-x {{ $key }} \
{{- end }}
{{- if eq .role "decode" }}
{{- range $key, $_ := .root.Values.trtllmEnv.decode }}
-x {{ $key }} \
{{- end }}
{{- end }}
{{- end }}
{{- end }}
