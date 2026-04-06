{{- define "postgresql.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "postgresql.secretName" -}}
{{- if .Values.secretNameOverride -}}
{{- .Values.secretNameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-secret" (include "postgresql.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "postgresql.labels" -}}
app.kubernetes.io/name: postgresql
app.kubernetes.io/instance: {{ include "postgresql.fullname" . }}
app.kubernetes.io/component: postgres
{{- end -}}
