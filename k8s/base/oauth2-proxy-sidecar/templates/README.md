# OAuth2 Proxy Custom Templates

This directory contains custom HTML templates for the OAuth2 Proxy sign-in and error pages.

## Templates

### sign_in.html
The login page shown to unauthenticated users. Features:
- Dark mode with theme toggle
- Cat Herding brand identity with embedded logo
- Modern, responsive design using Tailwind CSS
- Clear messaging about SSO for *.cat-herding.net domain
- Provider button with GitHub branding

### error.html
The error page shown when authentication fails or errors occur. Features:
- Consistent branding with sign-in page
- Displays error message from oauth2-proxy
- "Try Again" button to restart authentication
- Same dark mode and responsive design

## Customization

These templates use:
- **Tailwind CSS CDN** for styling (no build step required)
- **Base64 embedded logo** for faster loading
- **localStorage** for theme preference persistence
- **Template variables** from oauth2-proxy:
  - `{{.Logo}}` - Logo URL (unused, we use base64)
  - `{{.ProviderName}}` - OAuth provider name
  - `{{.SignInMessage}}` - Custom sign-in message
  - `{{.CustomLogin}}` - Enable custom login button
  - `{{.Footer}}` - Footer HTML
  - `{{.Error}}` - Error message (error.html only)

## Deployment

Templates are mounted into oauth2-proxy pods via the `oauth2-proxy-templates` ConfigMap:

```yaml
volumeMounts:
  - name: templates
    mountPath: /etc/oauth2-proxy/templates
    readOnly: true

volumes:
  - name: templates
    configMap:
      name: oauth2-proxy-templates
```

## Updating Templates

1. Edit the HTML files in this directory
2. Update the ConfigMap: `kubectl create configmap oauth2-proxy-templates --from-file=k8s/base/oauth2-proxy-sidecar/templates/ --dry-run=client -o yaml | kubectl apply -f -`
3. Restart pods to pick up changes: `kubectl rollout restart deployment <app-name>`

## Branding

To customize branding:
1. Replace the base64 logo in both files (currently Cat Herding logo from assets/logo-96.base64.txt)
2. Update the title and description text
3. Modify colors in the Tailwind classes
4. Update the provider button styling if using a different OAuth provider
