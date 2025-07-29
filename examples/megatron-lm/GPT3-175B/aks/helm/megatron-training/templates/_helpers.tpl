{{/*
Create a default fully qualified app name.
*/}}
{{- define "megatron-training.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "megatron-training.labels" -}}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Model size configuration
*/}}
{{- define "megatron-training.modelConfig" -}}
{{- if .Values.model.custom.numLayers }}
NUM_LAYERS={{ .Values.model.custom.numLayers }}
HIDDEN_SIZE={{ .Values.model.custom.hiddenSize }}
NUM_ATTENTION_HEADS={{ .Values.model.custom.numAttentionHeads }}
SEQ_LENGTH={{ .Values.model.custom.seqLength }}
TENSOR_MODEL_PARALLEL_SIZE={{ .Values.model.custom.tensorModelParallelSize }}
PIPELINE_MODEL_PARALLEL_SIZE={{ .Values.model.custom.pipelineModelParallelSize }}
{{- else if eq .Values.model.size "175b" }}
NUM_LAYERS=96
HIDDEN_SIZE=12288
NUM_ATTENTION_HEADS=96
SEQ_LENGTH=2048
TENSOR_MODEL_PARALLEL_SIZE=8
PIPELINE_MODEL_PARALLEL_SIZE=16
{{- else if eq .Values.model.size "30b" }}
NUM_LAYERS=48
HIDDEN_SIZE=7168
NUM_ATTENTION_HEADS=56
SEQ_LENGTH=2048
TENSOR_MODEL_PARALLEL_SIZE=4
PIPELINE_MODEL_PARALLEL_SIZE=8
{{- else if eq .Values.model.size "13b" }}
NUM_LAYERS=40
HIDDEN_SIZE=5120
NUM_ATTENTION_HEADS=40
SEQ_LENGTH=2048
TENSOR_MODEL_PARALLEL_SIZE=2
PIPELINE_MODEL_PARALLEL_SIZE=4
{{- else if eq .Values.model.size "1.3b" }}
NUM_LAYERS=24
HIDDEN_SIZE=2048
NUM_ATTENTION_HEADS=16
SEQ_LENGTH=2048
TENSOR_MODEL_PARALLEL_SIZE=1
PIPELINE_MODEL_PARALLEL_SIZE=2
{{- else if eq .Values.model.size "857m" }}
NUM_LAYERS=24
HIDDEN_SIZE=1024
NUM_ATTENTION_HEADS=16
SEQ_LENGTH=2048
TENSOR_MODEL_PARALLEL_SIZE=1
PIPELINE_MODEL_PARALLEL_SIZE=1
{{- else if eq .Values.model.size "375m" }}
NUM_LAYERS=12
HIDDEN_SIZE=512
NUM_ATTENTION_HEADS=8
SEQ_LENGTH=1024
TENSOR_MODEL_PARALLEL_SIZE=1
PIPELINE_MODEL_PARALLEL_SIZE=1
{{- else if eq .Values.model.size "125m" }}
NUM_LAYERS=12
HIDDEN_SIZE=768
NUM_ATTENTION_HEADS=12
SEQ_LENGTH=1024
TENSOR_MODEL_PARALLEL_SIZE=1
PIPELINE_MODEL_PARALLEL_SIZE=1
{{- else }}
# Default to 375m
NUM_LAYERS=12
HIDDEN_SIZE=512
NUM_ATTENTION_HEADS=8
SEQ_LENGTH=1024
TENSOR_MODEL_PARALLEL_SIZE=1
PIPELINE_MODEL_PARALLEL_SIZE=1
{{- end }}
{{- end }}
