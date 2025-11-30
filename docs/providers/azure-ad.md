# Azure AD OAuth2 Setup

This guide shows how to configure Azure Active Directory as the OAuth2 provider for the OAuth2 Sidecar.

## 1. Register an Application in Azure AD

1. Go to **Azure Portal → Azure Active Directory → App registrations**
2. Click **New registration**
3. Set:
   - **Name**: `OAuth2 Sidecar`
   - **Supported account types**: Choose based on your scenario
   - **Redirect URI**: `https://my-app.example.com/oauth2/callback`
4. Click **Register**

## 2. Configure API Permissions

1. In your app registration, go to **API permissions**
2. Ensure `openid` and `profile` scopes are included
3. Add additional scopes if needed (e.g. `email`)

## 3. Collect Required Values

From your app registration:
- **Application (client) ID**
- **Directory (tenant) ID**
- **Client Secret** (create one under **Certificates & secrets**)

## 4. Configure the Helm Chart

In your `values.yaml`:

```yaml
domain: example.com
cookieDomain: .example.com

oauth:
  provider: azure
  clientID: "YOUR_CLIENT_ID"
  clientSecret: "YOUR_CLIENT_SECRET"
  cookieSecret: "$(openssl rand -base64 32)"

  azure:
    tenant: "YOUR_TENANT_ID"
    resource: "api://YOUR_APP_ID_URI"  # Optional: custom resource/audience
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
  provider: azure
  existingSecret: oauth2-proxy-secret
```

## 5. Test the Flow

1. Deploy the Helm chart with your configuration
2. Deploy an example app (e.g. `examples/simple-app`)
3. Open `https://simple-app.example.com`
4. You should be redirected to Azure AD to sign in
5. After successful login, you will be redirected back to your app
