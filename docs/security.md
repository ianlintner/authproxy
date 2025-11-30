# Security Best Practices

Guidelines for running OAuth2 Sidecar in production.

## 1. Secrets Management

- Never commit client IDs/secrets to Git.
- Use Kubernetes Secrets or an external secret manager.
- Rotate `cookieSecret` regularly.

## 2. TLS

- Always terminate TLS at the Istio Gateway.
- Use strong ciphers and TLS 1.2+.
- Automate certificate renewal (e.g. cert-manager).

## 3. Least Privilege

- Keep the oauth2-proxy sidecar running as non-root (default in this chart).
- Do not grant unnecessary RBAC permissions.

## 4. Session Security

- Keep `cookieSecure: true` in production.
- Use `SameSite=lax` or `Strict` where possible.
- Set reasonable session expiry and refresh intervals.

## 5. Provider Configuration

- Limit access via:
  - GitHub org/team
  - Google Workspace domain
  - Azure AD tenant
- Request only required scopes.

## 6. Logging & Monitoring

- Enable access logs for oauth2-proxy.
- Monitor 4xx/5xx rates and login failures.
- Use tools like Prometheus/Grafana for metrics.

## 7. Multi-Tenancy

- Use separate client IDs/secrets per tenant if needed.
- Isolate apps by namespace.

## 8. Supply Chain

- Pin image tags (no `:latest`).
- Use trusted registries.
- Scan images for vulnerabilities.

## 9. Backup & Recovery

- Backup configuration (Helm values, manifests).
- Be prepared to roll back via `helm rollback`.

## 10. Regular Reviews

- Periodically review:
  - Provider app registrations
  - RBAC roles
  - Network policies
