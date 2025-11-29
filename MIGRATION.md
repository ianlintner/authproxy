# Migration to Sidecar-Based OAuth2 Proxy

This document summarizes the changes from the centralized ext_authz pattern to the simpler sidecar pattern.

## What Changed

### Removed (Old Centralized Pattern)

- ❌ `k8s/base/oauth2-proxy/` - Centralized oauth2-proxy deployment
- ❌ `k8s/base/istio/ext-authz-filter.yaml` - Complex EnvoyFilter for external authorization
- ❌ `k8s/base/istio/authorization-policy-oauth-bypass.yaml` - Auth bypass policy
- ❌ `k8s/base/istio/virtualservice-auth.yaml` - Auth service routing
- ❌ `k8s/apps/example-app/` - Old example with centralized auth
- ❌ `scripts/add-app.sh` - Old script for centralized pattern

### Added (New Sidecar Pattern)

- ✅ `k8s/base/oauth2-proxy-sidecar/` - Sidecar configuration
  - `configmap-sidecar.yaml` - OAuth2 proxy config
  - `secret.yaml.example` - OAuth credentials template
  - `sidecar-template.yaml` - Container spec documentation
  - `kustomization.yaml` - Kustomize config
- ✅ `k8s/apps/example-app-sidecar/` - Complete example with sidecar
  - `deployment.yaml` - App + oauth2-proxy sidecar
  - `service.yaml` - Service exposing port 4180
  - `virtualservice.yaml` - Routes to sidecar
  - `README.md` - Usage guide
- ✅ `scripts/add-sidecar.sh` - Helper to add auth to existing apps
- ✅ Updated `scripts/setup.sh` - Deploys sidecar infrastructure
- ✅ Updated `scripts/validate.sh` - Validates sidecar setup
- ✅ Updated `README.md` - New architecture documentation
- ✅ Updated `docs/ARCHITECTURE.md` - Detailed sidecar design
- ✅ Updated `docs/ADDING_APPS.md` - Step-by-step guide

## Key Architecture Changes

### Old Pattern: Centralized ext_authz

```
Browser → Istio Gateway → ext_authz filter → oauth2-proxy service
                              ↓
                         (if authenticated)
                              ↓
                         Application Pod
```

**Issues**:
- Complex Istio EnvoyFilter configuration
- Centralized oauth2-proxy single point of failure
- Hard to debug (auth logic separate from app)
- Difficult to customize per-app

### New Pattern: Sidecar

```
Browser → Istio Gateway → Service → Pod [oauth2-proxy → app]
```

**Benefits**:
- ✅ Simpler Istio config (just Gateway)
- ✅ No centralized service
- ✅ Easy to debug (logs in same pod)
- ✅ Per-app customization
- ✅ Auto-scales with app

## Migration Steps

### For New Applications

Use the new pattern from the start:

```bash
# 1. Deploy infrastructure
./scripts/setup.sh

# 2. Deploy your app using example-app-sidecar as template
kubectl apply -k k8s/apps/example-app-sidecar/

# Or use the helper
./scripts/add-sidecar.sh myapp default 8080 myapp.cat-herding.net
```

### For Existing Applications (Already Using Old Pattern)

1. **Test with one app first**:
   ```bash
   ./scripts/add-sidecar.sh test-app default 8080 test-app.cat-herding.net
   ```

2. **Verify it works**:
   ```bash
   curl -v https://test-app.cat-herding.net
   ```

3. **Migrate remaining apps** one at a time

4. **After all apps migrated**, remove old infrastructure:
   ```bash
   # Delete old centralized oauth2-proxy
   kubectl delete deployment oauth2-proxy -n default
   kubectl delete service oauth2-proxy -n default
   
   # Delete old Istio resources
   kubectl delete envoyfilter ext-authz -n aks-istio-ingress
   kubectl delete virtualservice oauth2-proxy -n default
   ```

## Configuration Changes

### OAuth Secret

**Location changed**:
- Old: `k8s/base/oauth2-proxy/secret.yaml`
- New: `k8s/base/oauth2-proxy-sidecar/secret.yaml`

**Content**: Same (client-id, client-secret, cookie-secret)

**Migration**: Copy your existing secret to new location

### ConfigMap

**Location changed**:
- Old: `k8s/base/oauth2-proxy/configmap.yaml`
- New: `k8s/base/oauth2-proxy-sidecar/configmap-sidecar.yaml`

**Key changes**:
- `upstreams` now configurable per-app via env var
- Removed server-side auth check endpoint config

### Per-App Configuration

**Old pattern**:
- Add label: `auth.cat-herding.net/enabled: "true"`
- Create AuthorizationPolicy with CUSTOM action
- VirtualService routes to app port

**New pattern**:
- Add oauth2-proxy sidecar container to deployment
- Service exposes port 4180 (oauth2-proxy)
- VirtualService routes to port 4180

## Script Changes

### setup.sh

**Old**:
- Deployed centralized oauth2-proxy deployment
- Deployed ext-authz EnvoyFilter
- Deployed auth VirtualService

**New**:
- Deploys oauth2-proxy-sidecar ConfigMap
- Deploys Istio Gateway only
- Much simpler!

### add-app.sh → add-sidecar.sh

**Old** (`add-app.sh`):
- Created VirtualService
- Created AuthorizationPolicy with CUSTOM action
- App label `auth.cat-herding.net/enabled: "true"`

**New** (`add-sidecar.sh`):
- Patches deployment with oauth2-proxy sidecar
- Updates service to expose port 4180
- Creates/updates VirtualService to route to 4180

## Traffic Flow Changes

### Old Pattern

```
1. Request → Istio Gateway
2. ext_authz filter intercepts
3. Filter calls oauth2-proxy service: GET /oauth2/auth
4. If not authenticated → 302 to OAuth provider
5. If authenticated → forward to app with headers
```

### New Pattern

```
1. Request → Istio Gateway
2. Routes to Service port 4180
3. Service routes to oauth2-proxy sidecar
4. If not authenticated → 302 to OAuth provider
5. If authenticated → proxy to localhost:8080 (app)
```

**Simpler**: No filter, no external auth check, just direct routing

## Benefits Summary

| Aspect | Old (Centralized) | New (Sidecar) | Winner |
|--------|------------------|---------------|---------|
| **Complexity** | High (EnvoyFilter) | Low (just containers) | ✅ Sidecar |
| **Debugging** | Hard (separate pods) | Easy (same pod) | ✅ Sidecar |
| **Scaling** | Manual | Auto (with app) | ✅ Sidecar |
| **Customization** | Global only | Per-app | ✅ Sidecar |
| **Failure Impact** | All apps | One app | ✅ Sidecar |
| **Performance** | Network hop | Localhost | ✅ Sidecar |
| **Portability** | Istio-specific | Standard K8s | ✅ Sidecar |

## Breaking Changes

⚠️ **Important**: Apps using the old pattern will need to be updated

1. **VirtualService change**: Must route to port 4180 instead of app port
2. **Service change**: Must expose port 4180
3. **Deployment change**: Must include oauth2-proxy sidecar

**Migration is required** - old pattern will not work after removing centralized oauth2-proxy

## Rollback Plan

If you need to rollback:

1. Redeploy old infrastructure:
   ```bash
   git checkout main  # or your old branch
   ./scripts/setup.sh
   ```

2. Remove sidecar from apps:
   ```bash
   kubectl rollout undo deployment/<app-name>
   ```

3. Restore old VirtualServices

## Testing Checklist

After migration, verify:

- [ ] Apps are accessible at their URLs
- [ ] OAuth login flow works
- [ ] User headers are available in apps
- [ ] SSO works across multiple apps
- [ ] Cookie domain is `.cat-herding.net`
- [ ] TLS is working
- [ ] Logs are accessible
- [ ] Resource usage is acceptable

## Support

- **Documentation**: See `README.md`, `docs/ARCHITECTURE.md`, `docs/ADDING_APPS.md`
- **Example**: Check `k8s/apps/example-app-sidecar/`
- **Validation**: Run `./scripts/validate.sh`
- **Issues**: Check troubleshooting section in docs

## Timeline

This migration was completed on the `sidecar` branch. The old centralized pattern is deprecated and will be removed.

**Recommendation**: Migrate to sidecar pattern for all new deployments.
