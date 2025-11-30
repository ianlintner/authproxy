# Generic OIDC Setup

This guide shows how to configure a generic OpenID Connect (OIDC) provider for the OAuth2 Sidecar.

## 1. Create a Client in Your OIDC Provider

Steps vary by provider (Keycloak, Auth0, Okta, etc.), but generally:

1. Create a new application/client
2. Set the **redirect URI** to:
   - `https://my-app.example.com/oauth2/callback`
3. Enable standard OIDC scopes: `openid`, `profile`, `email`

Collect the following values:
- **Client ID**
- **Client Secret**
- **Issuer URL** (e.g. `https://auth.example.com/realms/myrealm`)

## 2. Configure the Helm Chart

In your `values.yaml`:

```yaml
domain: example.com
cookieDomain: .example.com

oauth:
  provider: oidc
  clientID: "YOUR_CLIENT_ID"
  clientSecret: "YOUR_CLIENT_SECRET"
  cookieSecret: "$(openssl rand -base64 32)"

  oidc:
    issuerURL: "https://auth.example.com/realms/myrealm"
    extraScopes:
      - "profile"
      - "email"
```

Or using a pre-created secret:

```bash
kubectl create secret generic oauth2-proxy-secret \
  --from-literal=client-id=YOUR_CLIENT_ID \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  --from-literal=cookie-secret=$(openssl rand -base64 32)
```

```yaml
oauth:
  provider: oidc
  existingSecret: oauth2-proxy-secret

  oidc:
    issuerURL: "https://auth.example.com/realms/myrealm"
    extraScopes:
      - "profile"
      - "email"
```

## 3. Test the Flow

1. Deploy the Helm chart with your configuration
2. Deploy an example app (e.g. `examples/simple-app`)
3. Open `https://simple-app.example.com`
4. You should be redirected to your OIDC provider to sign in
5. After successful login, you will be redirected back to your app
