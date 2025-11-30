{{/*
Expand the name of the chart.
*/}}
{{- define "oauth2-sidecar.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
*/}}
{{- define "oauth2-sidecar.fullname" -}}
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
{{- define "oauth2-sidecar.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "oauth2-sidecar.labels" -}}
helm.sh/chart: {{ include "oauth2-sidecar.chart" . }}
{{ include "oauth2-sidecar.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "oauth2-sidecar.selectorLabels" -}}
app.kubernetes.io/name: {{ include "oauth2-sidecar.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{/*
Create the name of the service account to use
*/}}
{{- define "oauth2-sidecar.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "oauth2-sidecar.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{/*
Get the secret name
*/}}
{{- define "oauth2-sidecar.secretName" -}}
{{- if .Values.oauth.existingSecret }}
{{- .Values.oauth.existingSecret }}
{{- else }}
{{- .Values.secretName | default "oauth2-proxy-secret" }}
{{- end }}
{{- end }}

{{/*
Get cookie secret - requires either oauth.cookieSecret or oauth.existingSecret
SECURITY: Do not use auto-generated secrets in production.
Generate with: openssl rand -base64 32 | tr -- '+/' '-_'
*/}}
{{- define "oauth2-sidecar.cookieSecret" -}}
{{- if .Values.oauth.cookieSecret }}
{{- .Values.oauth.cookieSecret }}
{{- else if .Values.oauth.existingSecret }}
{{- /* When using existingSecret, cookie-secret should be in that secret */ -}}
{{- else }}
{{- fail "SECURITY ERROR: oauth.cookieSecret is required when not using oauth.existingSecret. Generate with: openssl rand -base64 32 | tr -- '+/' '-_'" }}
{{- end }}
{{- end }}

{{/*
Get OAuth provider configuration
*/}}
{{- define "oauth2-sidecar.providerConfig" -}}
{{- if eq .Values.oauth.provider "github" }}
{{- if .Values.oauth.github.org }}
- --github-org={{ .Values.oauth.github.org }}
{{- end }}
{{- if .Values.oauth.github.team }}
- --github-team={{ .Values.oauth.github.team }}
{{- end }}
{{- else if eq .Values.oauth.provider "google" }}
{{- if .Values.oauth.google.hostedDomain }}
- --google-hosted-domain={{ .Values.oauth.google.hostedDomain }}
{{- end }}
{{- else if eq .Values.oauth.provider "azure" }}
{{- if .Values.oauth.azure.tenant }}
- --azure-tenant={{ .Values.oauth.azure.tenant }}
{{- end }}
{{- if .Values.oauth.azure.resource }}
- --resource={{ .Values.oauth.azure.resource }}
{{- end }}
{{- else if eq .Values.oauth.provider "oidc" }}
{{- if .Values.oauth.oidc.issuerURL }}
- --oidc-issuer-url={{ .Values.oauth.oidc.issuerURL }}
{{- end }}
{{- range .Values.oauth.oidc.extraScopes }}
- --scope={{ . }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Sidecar container spec
*/}}
{{- define "oauth2-sidecar.sidecarContainer" -}}
- name: oauth2-proxy
  image: "{{ .Values.sidecar.image.repository }}:{{ .Values.sidecar.image.tag }}"
  imagePullPolicy: {{ .Values.sidecar.image.pullPolicy }}
  args:
    - --config=/etc/oauth2-proxy/oauth2_proxy.cfg
    - --http-address=0.0.0.0:{{ .Values.sidecar.port }}
    {{- if .Values.customTemplates.enabled }}
    - --custom-templates-dir=/etc/oauth2-proxy/templates
    {{- end }}
    {{- include "oauth2-sidecar.providerConfig" . | nindent 4 }}
    {{- range .Values.extraArgs }}
    - {{ . }}
    {{- end }}
  env:
    - name: OAUTH2_PROXY_CLIENT_ID
      valueFrom:
        secretKeyRef:
          name: {{ include "oauth2-sidecar.secretName" . }}
          key: client-id
    - name: OAUTH2_PROXY_CLIENT_SECRET
      valueFrom:
        secretKeyRef:
          name: {{ include "oauth2-sidecar.secretName" . }}
          key: client-secret
    - name: OAUTH2_PROXY_COOKIE_SECRET
      valueFrom:
        secretKeyRef:
          name: {{ include "oauth2-sidecar.secretName" . }}
          key: cookie-secret
    - name: OAUTH2_PROXY_UPSTREAMS
      value: "http://127.0.0.1:{{ .Values.sidecar.upstreamPort }}"
    - name: OAUTH2_PROXY_REDIRECT_URL
      value: "https://$(HOSTNAME).{{ .Values.domain }}/oauth2/callback"
  ports:
    - name: http
      containerPort: {{ .Values.sidecar.port }}
      protocol: TCP
  volumeMounts:
    - name: config
      mountPath: /etc/oauth2-proxy
      readOnly: true
    {{- if .Values.customTemplates.enabled }}
    - name: templates
      mountPath: /etc/oauth2-proxy/templates
      readOnly: true
    {{- end }}
  {{- with .Values.sidecar.livenessProbe }}
  livenessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.sidecar.readinessProbe }}
  readinessProbe:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.sidecar.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  {{- with .Values.sidecar.securityContext }}
  securityContext:
    {{- toYaml . | nindent 4 }}
  {{- end }}
{{- end }}
