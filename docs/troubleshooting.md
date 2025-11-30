# Troubleshooting

Common issues and how to diagnose/fix them.

## 1. 403 Forbidden from Istio/Gateway

### Symptoms
- `curl -I https://my-app.example.com` returns `HTTP/2 403`
- Browser shows generic 403 page

### Causes
- AuthorizationPolicy blocking traffic
- VirtualService routing to wrong service/port

### Checks
```bash
kubectl get authorizationpolicy -A
kubectl get virtualservice -A
kubectl describe virtualservice my-app -n default
```

Ensure your VirtualService routes to the service backing the oauth2-proxy sidecar (port 4180).

## 2. Redirect Loop

### Symptoms
- Browser keeps redirecting between your app and OAuth provider

### Causes
- Cookie domain mismatch
- Wrong redirect URL

### Checks
- `cookieDomain` must start with `.` and match your domain
- `OAUTH2_PROXY_REDIRECT_URL` must match the callback URL configured in your provider

## 3. Login Page Not Using Custom Branding

### Symptoms
- Default oauth2-proxy login page appears

### Causes
- Custom templates ConfigMap not mounted
- `customTemplates.enabled` set to `false`

### Checks
```bash
kubectl get configmap oauth2-proxy-templates
kubectl describe pod <pod> | grep oauth2-proxy-templates
```

## 4. 500 Error from oauth2-proxy

### Symptoms
- Error page from oauth2-proxy

### Checks
```bash
kubectl logs deployment/my-app -c oauth2-proxy
```

Look for:
- Misconfigured provider settings
- Invalid client ID/secret

## 5. Users from Wrong Domain Can Log In

### Causes
- Email/domain restrictions not configured

### Fix
- For Google: set `oauth.google.hostedDomain`
- For GitHub: set `oauth.github.org` and/or `oauth.github.team`
- For generic: use `email.domains` filters

## 6. TLS/Certificate Issues

If creating a new Istio Gateway with the chart:

- Ensure `istio.gateway.tls.credentialName` points to a valid TLS secret
- Secret must be in the same namespace as the gateway

## 7. Verifying Headers in Your App

To debug what headers your app receives, add an endpoint that dumps headers:

```bash
curl -s https://my-app.example.com/headers
```

Your app should log or return headers like:
- `X-Auth-Request-User`
- `X-Auth-Request-Email`
- `X-Forwarded-User`

## 8. Still Stuck?

Collect the following before asking for help:
- `helm get values oauth2-sidecar -n <ns>`
- `kubectl get pods,svc,virtualservice,authorizationpolicy -n <ns>`
- Logs from oauth2-proxy sidecar container
