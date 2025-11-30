# GitHub OAuth2 Setup

This guide shows how to configure GitHub as the OAuth2 provider for the OAuth2 Sidecar.

## 1. Create a GitHub OAuth App

1. Go to **Settings → Developer settings → OAuth Apps**
2. Click **New OAuth App**
3. Set the following values:
   - **Application name**: `OAuth2 Sidecar`
   - **Homepage URL**: `https://your-domain.example.com`
   - **Authorization callback URL**: `https://my-app.example.com/oauth2/callback`
4. Click **Register application**

Copy the following values:
- **Client ID**
- **Client Secret**

## 2. Configure the Helm Chart

In your `values.yaml` or via `--set` flags:

```yaml
domain: example.com
cookieDomain: .example.com

oauth:
  provider: github
  clientID: "YOUR_CLIENT_ID"
  clientSecret: "YOUR_CLIENT_SECRET"
  cookieSecret: "$(openssl rand -base64 32)"

  github:
    org: ""   # Optional: restrict to org
    team: ""  # Optional: restrict to team
```

Or using the secret-based approach:

```bash
kubectl create secret generic oauth2-proxy-secret \
  --from-literal=client-id=YOUR_CLIENT_ID \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  --from-literal=cookie-secret=$(openssl rand -base64 32)
```

And in `values.yaml`:

```yaml
oauth:
  provider: github
  existingSecret: oauth2-proxy-secret
```

## 3. Restrict Access by Organization or Team

To restrict access to a single GitHub organization:

```yaml
oauth:
  provider: github
  github:
    org: "my-org"
```

To restrict access to a specific team (requires `org`):

```yaml
oauth:
  provider: github
  github:
    org: "my-org"
    team: "my-team"
```

## 4. Test the Flow

1. Deploy the Helm chart with your configuration
2. Deploy an example app (e.g. `examples/simple-app`)
3. Open `https://simple-app.example.com`
4. You should be redirected to GitHub to sign in
5. After successful login, you will be redirected back to your app
