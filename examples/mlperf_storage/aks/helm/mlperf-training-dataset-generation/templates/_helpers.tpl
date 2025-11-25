{{/*
Expand the name of the chart.
*/}}
{{- define "mlperf-training-dataset-generation.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "mlperf-training-dataset-generation.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Chart name and version label
*/}}
{{- define "mlperf-training-dataset-generation.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "mlperf-training-dataset-generation.labels" -}}
helm.sh/chart: {{ include "mlperf-training-dataset-generation.chart" . }}
{{ include "mlperf-training-dataset-generation.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "mlperf-training-dataset-generation.selectorLabels" -}}
app.kubernetes.io/name: {{ include "mlperf-training-dataset-generation.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
