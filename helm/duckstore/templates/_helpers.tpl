{{/*
==============================================================================
_helpers.tpl - Reusable Template Helpers for DuckStore
==============================================================================
This file contains named templates (macros) written in Go template syntax.
They provide consistent resource naming, standard Kubernetes labels, and
dynamically generated connection endpoints across the entire Helm chart.
==============================================================================
*/}}

{{/*
Expand the name of the chart.
Truncated at 63 characters because Kubernetes resource names are limited to 63 chars (RFC 1123).
*/}}
{{- define "duckstore.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "duckstore.fullname" -}}
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
Create chart name and version as used by the chart label.
Encodes chart name and version according to Helm conventions.
*/}}
{{- define "duckstore.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common standard labels applied across all DuckStore resources.
Provides tracking metadata for GitOps, observability, and Kubernetes auditing.
*/}}
{{- define "duckstore.labels" -}}
helm.sh/chart: {{ include "duckstore.chart" . }}
app.kubernetes.io/name: {{ include "duckstore.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: duckstore
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
{{- end }}

{{/*
Backend-specific selector and tracking labels.
Preserves backwards compatibility with existing 'app: duck-api' selectors.
*/}}
{{- define "duckstore.backend.labels" -}}
{{ include "duckstore.labels" . }}
app: duck-api
tier: backend
{{- end }}

{{/*
Frontend-specific selector and tracking labels.
Preserves backwards compatibility with existing 'app: duck-web' selectors.
*/}}
{{- define "duckstore.frontend.labels" -}}
{{ include "duckstore.labels" . }}
app: duck-web
tier: frontend
{{- end }}

{{/*
Dynamic internal Backend API URL calculation.
Computes: http://<backend-service-name>.<backend-namespace>.svc.cluster.local:<port>
Allows the frontend to dynamically find the backend API even if names or namespaces change.
*/}}
{{- define "duckstore.backendUrl" -}}
{{- if .Values.frontend.env.backendUrl }}
{{- .Values.frontend.env.backendUrl }}
{{- else }}
{{- printf "http://%s.%s.svc.cluster.local:%d" .Values.backend.service.name .Values.backend.namespace (int .Values.backend.service.port) }}
{{- end }}
{{- end }}
