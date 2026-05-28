{{/*
Expand the name of the chart.
*/}}
{{- define "uniflow.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "uniflow.fullname" -}}
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
*/}}
{{- define "uniflow.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "uniflow.labels" -}}
helm.sh/chart: {{ include "uniflow.chart" . }}
{{ include "uniflow.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "uniflow.selectorLabels" -}}
app.kubernetes.io/name: {{ include "uniflow.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
API selector labels
*/}}
{{- define "uniflow.api.selectorLabels" -}}
{{ include "uniflow.selectorLabels" . }}
app.kubernetes.io/component: api
{{- end }}

{{/*
Worker selector labels
*/}}
{{- define "uniflow.worker.selectorLabels" -}}
{{ include "uniflow.selectorLabels" . }}
app.kubernetes.io/component: worker
{{- end }}

{{/*
Scheduler selector labels
*/}}
{{- define "uniflow.scheduler.selectorLabels" -}}
{{ include "uniflow.selectorLabels" . }}
app.kubernetes.io/component: scheduler
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "uniflow.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "uniflow.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Return the proper image name
*/}}
{{- define "uniflow.image" -}}
{{- $registryName := .imageRoot.registry | default "" -}}
{{- $repositoryName := .imageRoot.repository -}}
{{- $tag := .imageRoot.tag | default .chart.AppVersion | toString -}}
{{- if $registryName }}
{{- printf "%s/%s:%s" $registryName $repositoryName $tag -}}
{{- else }}
{{- printf "%s:%s" $repositoryName $tag -}}
{{- end }}
{{- end }}

{{/*
API image
*/}}
{{- define "uniflow.api.image" -}}
{{- include "uniflow.image" (dict "imageRoot" .Values.api.image "chart" .Chart) -}}
{{- end }}

{{/*
Worker image
*/}}
{{- define "uniflow.worker.image" -}}
{{- include "uniflow.image" (dict "imageRoot" .Values.worker.image "chart" .Chart) -}}
{{- end }}

{{/*
Scheduler image
*/}}
{{- define "uniflow.scheduler.image" -}}
{{- include "uniflow.image" (dict "imageRoot" .Values.scheduler.image "chart" .Chart) -}}
{{- end }}

{{/*
Database host
*/}}
{{- define "uniflow.database.host" -}}
{{- if .Values.secrets.database.host }}
{{- .Values.secrets.database.host }}
{{- else if .Values.postgresql.enabled }}
{{- printf "%s-postgresql" (include "uniflow.fullname" .) }}
{{- else }}
{{- fail "Database host must be specified when postgresql.enabled is false" }}
{{- end }}
{{- end }}

{{/*
Redis host
*/}}
{{- define "uniflow.redis.host" -}}
{{- if .Values.secrets.redis.host }}
{{- .Values.secrets.redis.host }}
{{- else if .Values.redis.enabled }}
{{- printf "%s-redis-master" (include "uniflow.fullname" .) }}
{{- else }}
{{- fail "Redis host must be specified when redis.enabled is false" }}
{{- end }}
{{- end }}

{{/*
RabbitMQ host
*/}}
{{- define "uniflow.rabbitmq.host" -}}
{{- if .Values.secrets.rabbitmq.host }}
{{- .Values.secrets.rabbitmq.host }}
{{- else if .Values.rabbitmq.enabled }}
{{- printf "%s-rabbitmq" (include "uniflow.fullname" .) }}
{{- else }}
{{- fail "RabbitMQ host must be specified when rabbitmq.enabled is false" }}
{{- end }}
{{- end }}

{{/*
Create secret name
*/}}
{{- define "uniflow.secretName" -}}
{{- printf "%s-secrets" (include "uniflow.fullname" .) }}
{{- end }}

{{/*
Create configmap name
*/}}
{{- define "uniflow.configMapName" -}}
{{- printf "%s-config" (include "uniflow.fullname" .) }}
{{- end }}

{{/*
Common environment variables for all components
*/}}
{{- define "uniflow.commonEnv" -}}
- name: POD_NAME
  valueFrom:
    fieldRef:
      fieldPath: metadata.name
- name: POD_NAMESPACE
  valueFrom:
    fieldRef:
      fieldPath: metadata.namespace
- name: POD_IP
  valueFrom:
    fieldRef:
      fieldPath: status.podIP
- name: DB_HOST
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: db-host
- name: DB_PORT
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: db-port
- name: DB_NAME
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: db-name
- name: DB_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: db-user
- name: DB_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: db-password
- name: REDIS_HOST
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: redis-host
- name: REDIS_PORT
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: redis-port
- name: REDIS_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: redis-password
- name: RABBITMQ_HOST
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: rabbitmq-host
- name: RABBITMQ_PORT
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: rabbitmq-port
- name: RABBITMQ_USER
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: rabbitmq-user
- name: RABBITMQ_PASSWORD
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: rabbitmq-password
- name: JWT_SECRET
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: jwt-secret
{{- if .Values.secrets.llm.openaiApiKey }}
- name: OPENAI_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: openai-api-key
      optional: true
{{- end }}
{{- if .Values.secrets.llm.anthropicApiKey }}
- name: ANTHROPIC_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: anthropic-api-key
      optional: true
{{- end }}
{{- if .Values.secrets.llm.googleApiKey }}
- name: GOOGLE_API_KEY
  valueFrom:
    secretKeyRef:
      name: {{ include "uniflow.secretName" . }}
      key: google-api-key
      optional: true
{{- end }}
{{- with .Values.extraEnv }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end }}
