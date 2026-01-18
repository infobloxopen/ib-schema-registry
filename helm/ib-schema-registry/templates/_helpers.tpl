{{/*
Expand the name of the chart.
Use fixed "ib-schema-registry" for labels to maintain compatibility,
even though Chart.yaml name is "ib-schema-registry-chart" to avoid OCI collision.
*/}}
{{- define "ib-schema-registry.name" -}}
{{- default "ib-schema-registry" .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
Use fixed "ib-schema-registry" for resource names to maintain compatibility.
*/}}
{{- define "ib-schema-registry.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default "ib-schema-registry" .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "ib-schema-registry.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "ib-schema-registry.labels" -}}
helm.sh/chart: {{ include "ib-schema-registry.chart" . }}
{{ include "ib-schema-registry.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "ib-schema-registry.selectorLabels" -}}
app.kubernetes.io/name: {{ include "ib-schema-registry.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "ib-schema-registry.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "ib-schema-registry.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Construct the image name
*/}}
{{- define "ib-schema-registry.image" -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion }}
{{- printf "%s:%s" .Values.image.repository $tag }}
{{- end }}

{{/*
Validate required values
*/}}
{{- define "ib-schema-registry.validate" -}}
{{- if not .Values.config.kafkaBootstrapServers }}
{{- fail "config.kafkaBootstrapServers is required. Please set it to your Kafka bootstrap servers (e.g., 'kafka:9092')" }}
{{- end }}
{{- if lt (.Values.replicaCount | int) 0 }}
{{- fail "replicaCount must be a non-negative integer" }}
{{- end }}
{{- if and .Values.podDisruptionBudget.enabled (le (.Values.replicaCount | int) 1) }}
{{- fail "podDisruptionBudget.enabled requires replicaCount > 1 for high availability" }}
{{- end }}
{{- end }}

