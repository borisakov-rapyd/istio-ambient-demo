{{- define "demo-app.name" -}}
{{- default .Release.Name .Values.name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "demo-app.labels" -}}
app: {{ include "demo-app.name" . }}
app.kubernetes.io/name: {{ include "demo-app.name" . }}
app.kubernetes.io/managed-by: argocd
version: v1
{{- end -}}
