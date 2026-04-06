{{- define "auxarmory.fullname" -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.labels" -}}
app.kubernetes.io/managed-by: Helm
app.kubernetes.io/part-of: auxarmory
app.kubernetes.io/instance: {{ include "auxarmory.fullname" . }}
{{- end -}}

{{- define "auxarmory.web.name" -}}
{{- printf "%s-web" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.auth.name" -}}
{{- printf "%s-auth" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.api.name" -}}
{{- printf "%s-api" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.worker.name" -}}
{{- printf "%s-worker" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.sharedSecretName" -}}
{{- printf "%s-shared-secret" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.webSecretName" -}}
{{- printf "%s-web-secret" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.authSecretName" -}}
{{- printf "%s-auth-secret" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.apiSecretName" -}}
{{- printf "%s-api-secret" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.workerSecretName" -}}
{{- printf "%s-worker-secret" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.webConfigMapName" -}}
{{- printf "%s-web-config" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.authConfigMapName" -}}
{{- printf "%s-auth-config" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.apiConfigMapName" -}}
{{- printf "%s-api-config" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "auxarmory.workerConfigMapName" -}}
{{- printf "%s-worker-config" (include "auxarmory.fullname" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
