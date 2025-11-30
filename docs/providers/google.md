# Google OAuth2 Setup

This guide shows how to configure Google as the OAuth2 provider for the OAuth2 Sidecar.

## 1. Create OAuth Credentials in Google Cloud

1. Go to **Google Cloud Console → APIs & Services → Credentials**
2. Click **Create Credentials → OAuth client ID**
3. Choose **Web application**
4. Set **Authorized redirect URIs** to:
   - `https://my-app.example.com/oauth2/callback`
5. Click **Create**

Copy the following values:
- **Client ID**
- **Client Secret**

## 2. Configure the Helm Chart

In your `values.yaml`:

```yaml
domain: example.com
cookieDomain: .example.com

oauth:
  provider: google
  clientID: "YOUR_CLIENT_ID.apps.googleusercontent.com"
  clientSecret: "YOUR_CLIENT_SECRET"
  cookieSecret: "$(openssl rand -base64 32)"

  google:
    hostedDomain: "mycompany.com"  # Optional: restrict to your Google Workspace domain
```

Or using a pre-created secret:

```bash
kubectl create secret generic oauth2-proxy-secret \
  --from-literal=client-id=YOUR_CLIENT_ID.apps.googleusercontent.com \
  --from-literal=client-secret=YOUR_CLIENT_SECRET \
  --from-literal=cookie-secret=$(openssl rand -base64 32)
```

```yaml
oauth:
  provider: google
  existingSecret: oauth2-proxy-secret
```

## 3. Restrict to a Google Workspace Domain

To allow only users from a specific Google Workspace domain:

```yaml
oauth:
  provider: google
  google:
    hostedDomain: "mycompany.com"
```

## 4. Test the Flow

1. Deploy the Helm chart with your configuration
2. Deploy an example app (e.g. `examples/simple-app`)
3. Open `https://simple-app.example.com`
4. You should be redirected to Google to sign in
5. After successful login, you will be redirected back to your app
