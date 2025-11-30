# Configuration Guide

This document explains all configuration options available for the OAuth2 Sidecar Helm chart.

For the full default `values.yaml`, see `helm/oauth2-sidecar/values.yaml`.

## Top-Level Settings

### `domain`
- **Type**: string
- **Default**: `example.com`
- **Description**: Base domain for your applications.

### `cookieDomain`
- **Type**: string
- **Default**: `.example.com`
- **Description**: Cookie domain enabling SSO across subdomains.

---

## `oauth` (OAuth Provider Configuration)

### `oauth.provider`
- **Type**: string
- **Required**: yes
- **Values**: `github`, `google`, `azure`, `oidc`
- **Description**: Which OAuth2 provider to use.

### `oauth.clientID`
- **Type**: string
- **Required**: yes (unless `existingSecret` is used)

### `oauth.clientSecret`
- **Type**: string
- **Required**: yes (unless `existingSecret` is used)

### `oauth.cookieSecret`
- **Type**: string
- **Required**: recommended (auto-generated if empty, but not suitable for long-term production)
- **Description**: Secret for encrypting session cookies.

### `oauth.existingSecret`
- **Type**: string
- **Description**: Name of an existing secret containing:
  - `client-id`
  - `client-secret`
  - `cookie-secret`

### `oauth.github.*`
- `org`: Restrict access to a GitHub organization
- `team`: Restrict access to a GitHub team

### `oauth.google.*`
- `hostedDomain`: Restrict access to a Google Workspace domain

### `oauth.azure.*`
- `tenant`: Azure AD tenant ID
- `resource`: Optional custom resource/audience

### `oauth.oidc.*`
- `issuerURL`: OIDC issuer URL
- `extraScopes`: Additional scopes to request

---

## `istio` (Istio Integration)

### `istio.enabled`
- **Type**: bool
- **Default**: `true`
- **Description**: Enable Istio-specific resources.

### `istio.gateway.create`
- **Type**: bool
- **Default**: `true`
- **Description**: Create an Istio Gateway resource.

### `istio.gateway.existingGateway`
- **Type**: string
- **Description**: Use an existing gateway instead of creating one.

### `istio.gateway.tls.*`
- `credentialName`: Name of TLS secret
- `mode`: TLS mode (e.g. `SIMPLE`)
- `minProtocolVersion`: Minimum TLS version (`TLSV1_2`)

### `istio.ingressGateway.*`
- `selector`: Label selector for Istio ingress gateway
- `namespace`: Namespace of ingress gateway

---

## `sidecar` (OAuth2 Proxy Sidecar)

### `sidecar.image.*`
- `repository`: Container image repository
- `tag`: Image tag
- `pullPolicy`: Image pull policy

### `sidecar.resources.*`
- Kubernetes resource requests and limits.

### `sidecar.port`
- **Default**: `4180`
- **Description**: Port where oauth2-proxy listens.

### `sidecar.upstreamPort`
- **Default**: `8080`
- **Description**: Port of your application inside the pod.

### `sidecar.securityContext.*`
- Preconfigured for least privilege and non-root execution.

### `sidecar.livenessProbe` / `sidecar.readinessProbe`
- Health checks for oauth2-proxy.

---

## `session` (Session & Cookies)

### `session.cookieExpire`
- **Default**: `168h`
- **Description**: Session cookie expiry duration.

### `session.cookieRefresh`
- **Default**: `1h`
- **Description**: How often to refresh session.

### `session.cookieName`
- **Default**: `_oauth2_proxy`

### `session.cookieSecure`
- **Default**: `true`

### `session.cookieHttpOnly`
- **Default**: `true`

### `session.cookieSameSite`
- **Default**: `lax`

---

## `email` (Email/Domain Restrictions)

### `email.domains`
- **Default**: `['*']`
- **Description**: Allowed email domains. Set to specific domains to restrict access.

---

## `customTemplates`

### `customTemplates.enabled`
- **Default**: `true`
- **Description**: Enable custom branding for sign-in and error pages.

### `customTemplates.brandName`
- **Default**: `"SSO Portal"`

### `customTemplates.logo`
- **Default**: empty
- **Description**: Base64-encoded logo.

---

## `namespace`

- **Default**: `default`
- **Description**: Namespace where resources are deployed.

---

## Advanced Settings

- `extraArgs`: Additional oauth2-proxy arguments
- `configMapName`, `secretName`, `templatesConfigMapName`: Override resource names
- `serviceAccount.*`: Configure service account
- `podAnnotations`, `podLabels`: Additional metadata
- `nodeSelector`, `tolerations`, `affinity`: Scheduling controls

For detailed examples, see the `examples/` directory and provider-specific docs in `docs/providers/`.
