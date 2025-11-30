# Simple App Example

Minimal example showing how to secure a single application with OAuth2 Sidecar.

## Files

- `deployment.yaml` - Application + oauth2-proxy sidecar
- `service.yaml` - Service exposing the sidecar port
- `virtualservice.yaml` - Istio VirtualService routing external traffic

## Usage

1. Install the Helm chart (or base manifests) following the main README.
2. Apply the example manifests:

```bash
kubectl apply -f examples/simple-app/deployment.yaml
kubectl apply -f examples/simple-app/service.yaml
kubectl apply -f examples/simple-app/virtualservice.yaml
```

3. Open `https://simple-app.example.com` in your browser.

Update the domain and gateway references to match your environment.
