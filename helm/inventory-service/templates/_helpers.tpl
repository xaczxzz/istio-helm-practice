# helm/inventory-service/templates/_helpers.tpl
{{/*
Expand the name of the chart.
*/}}
{{- define "inventory-service.name" -}}
{{- include "common.name" . }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "inventory-service.fullname" -}}
{{- include "common.fullname" . }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "inventory-service.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "inventory-service.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "inventory-service.labels" -}}
{{- include "common.labels" . }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "inventory-service.selectorLabels" -}}
{{- include "common.selectorLabels" . }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "inventory-service.chart" -}}
{{- include "common.chart" . }}
{{- end }}