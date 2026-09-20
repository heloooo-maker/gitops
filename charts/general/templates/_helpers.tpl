{{/*
Expand the name of the chart.
*/}}
{{- define "gea.name" -}}
{{- default $.Release.Name $.Values.serviceName | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "gea.fullname" -}}
{{- default $.Release.Name $.Values.serviceName | trunc 63 | trimSuffix "-" -}}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "gea.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "gea.serviceAccountName" -}}
{{- if $.Values.serviceAccount.create }}
{{- default (include "gea.fullname" .) $.Values.serviceAccountName }}
{{- else }}
{{- default "default" $.Values.serviceAccountName }}
{{- end }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "gea.labels" -}}
app.kubernetes.io/name: {{ include "gea.name" . }}
helm.sh/chart: {{ include "gea.chart" . }}
{{- if $.Chart.AppVersion }}
app.kubernetes.io/version: {{ $.Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ $.Release.Service }}
{{- end -}}


{{- define "gea.env" -}}
{{- with . -}}
env:
{{- range $key, $val := . }}
- name: {{ $key }}
  {{- if hasPrefix "\"secret:" ($val | quote) }}
  valueFrom:
    secretKeyRef:
      name: {{$val | trimPrefix "secret:" | splitList "." | first }}
      key: {{ $val | splitList "." | rest | join "." }}
  {{- else if hasPrefix "\"configmap:" ($val | quote) }}
  valueFrom:
    configMapKeyRef:
      name: {{ $val | trimPrefix "configmap:" | splitList "." | first }}
      key: {{ $val | splitList "." | rest | join "." }}
  {{- else }}
  value: {{ $val | quote }}
  {{- end }}
{{- end }}
{{- end }}
{{- end -}}



{{- define "gea.kongplugins" -}}
{{- if $.Values.ingress.plugins -}}
{{- $dict := dict "plugins" (list) -}}
{{- range $.Values.ingress.plugins -}}
{{- $var := printf "%s" . | append $dict.plugins | set $dict "plugins" -}}
{{- end -}}
{{- join "," $dict.plugins }}
{{- with $.Values.ingress.annotations }}
{{- ($.Values.ingress.annotations | default dict) | toYaml | nindent 4 }}
{{- end }}
{{- else }}
{{- ($.Values.ingress.annotations | default dict) | toYaml | nindent 4 }}
{{- end }}
{{- end -}}

{{- define "gea.cmd" -}}
{{- with .command }}
command: {{ . | toYaml | nindent 2 }}
{{- end }}
{{- with .args }}
args: {{ . | toYaml | nindent 2 }}
{{- end }}
{{- end -}}


{{- define "gea.resources" -}}
{{- with . }}
resources: {{ . | toYaml | nindent 2 }}
{{- end }}
{{- end -}}
