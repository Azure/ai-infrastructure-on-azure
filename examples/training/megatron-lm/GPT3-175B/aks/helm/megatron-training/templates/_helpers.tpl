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
Model size derived parameter helpers.
Each helper returns the effective value for that parameter:
1. Explicit override if provided in values.yaml (e.g. model.numLayers)
2. Otherwise derived from model.size mapping
*/}}

{{- define "megatron-training.sizeMap" -}}
{{- /* Internal map for size presets */ -}}
{{- $size := .Values.model.size | default "375m" -}}
{{- if eq $size "175b" }}{"numLayers":96,"hiddenSize":12288,"numAttentionHeads":96,"seqLength":2048,"tensorModelParallelSize":8,"pipelineModelParallelSize":16}
{{- else if eq $size "30b" }}{"numLayers":48,"hiddenSize":7168,"numAttentionHeads":56,"seqLength":2048,"tensorModelParallelSize":4,"pipelineModelParallelSize":8}
{{- else if eq $size "13b" }}{"numLayers":40,"hiddenSize":5120,"numAttentionHeads":40,"seqLength":2048,"tensorModelParallelSize":2,"pipelineModelParallelSize":4}
{{- else if eq $size "1.3b" }}{"numLayers":24,"hiddenSize":2048,"numAttentionHeads":16,"seqLength":2048,"tensorModelParallelSize":1,"pipelineModelParallelSize":2}
{{- else if eq $size "857m" }}{"numLayers":24,"hiddenSize":1024,"numAttentionHeads":16,"seqLength":2048,"tensorModelParallelSize":1,"pipelineModelParallelSize":1}
{{- else if eq $size "375m" }}{"numLayers":12,"hiddenSize":512,"numAttentionHeads":8,"seqLength":1024,"tensorModelParallelSize":1,"pipelineModelParallelSize":1}
{{- else if eq $size "125m" }}{"numLayers":12,"hiddenSize":768,"numAttentionHeads":12,"seqLength":1024,"tensorModelParallelSize":1,"pipelineModelParallelSize":1}
{{- else }}{"numLayers":12,"hiddenSize":512,"numAttentionHeads":8,"seqLength":1024,"tensorModelParallelSize":1,"pipelineModelParallelSize":1}
{{- end -}}
{{- end }}

{{- define "megatron-training.param.numLayers" -}}
{{- if .Values.model.numLayers -}}{{ .Values.model.numLayers }}{{- else -}}{{- (include "megatron-training.sizeMap" . | fromJson).numLayers -}}{{- end -}}{{- end }}
{{- define "megatron-training.param.hiddenSize" -}}
{{- if .Values.model.hiddenSize -}}{{ .Values.model.hiddenSize }}{{- else -}}{{- (include "megatron-training.sizeMap" . | fromJson).hiddenSize -}}{{- end -}}{{- end }}
{{- define "megatron-training.param.numAttentionHeads" -}}
{{- if .Values.model.numAttentionHeads -}}{{ .Values.model.numAttentionHeads }}{{- else -}}{{- (include "megatron-training.sizeMap" . | fromJson).numAttentionHeads -}}{{- end -}}{{- end }}
{{- define "megatron-training.param.seqLength" -}}
{{- if .Values.model.seqLength -}}{{ .Values.model.seqLength }}{{- else -}}{{- (include "megatron-training.sizeMap" . | fromJson).seqLength -}}{{- end -}}{{- end }}
{{- define "megatron-training.param.tensorModelParallelSize" -}}
{{- if .Values.model.tensorModelParallelSize -}}{{ .Values.model.tensorModelParallelSize }}{{- else -}}{{- (include "megatron-training.sizeMap" . | fromJson).tensorModelParallelSize -}}{{- end -}}{{- end }}
{{- define "megatron-training.param.pipelineModelParallelSize" -}}
{{- if .Values.model.pipelineModelParallelSize -}}{{ .Values.model.pipelineModelParallelSize }}{{- else -}}{{- (include "megatron-training.sizeMap" . | fromJson).pipelineModelParallelSize -}}{{- end -}}{{- end }}
