# OAuth2 Sidecar for Kubernetes - Public Release Plan

## Vision
Transform this AKS-specific OAuth2 proxy implementation into a **generic, reusable Kubernetes OAuth2 authentication solution** that anyone can deploy with minimal configuration.

## Current State Issues
1. ❌ Hardcoded to `cat-herding.net` domain
2. ❌ AKS/Istio specific configuration
3. ❌ No package manager support (Helm/Kustomize remote)
4. ❌ Manual secret management required
5. ❌ Complex directory structure
6. ❌ Documentation assumes specific cluster setup

## Target State Goals
1. ✅ **Generic domain support** - Any domain via configuration
2. ✅ **Multi-cluster compatible** - Works on any Kubernetes with Istio
3. ✅ **Helm chart available** - `helm install oauth2-sidecar`
4. ✅ **Kustomize remote base** - `kustomize build github.com/...`
5. ✅ **Simple structure** - Clear separation of base vs examples
6. ✅ **One-command setup** - Interactive configuration wizard
7. ✅ **Multiple examples** - Different providers and use cases
8. ✅ **Professional docs** - Architecture diagrams, troubleshooting

## Implementation Plan

### Phase 1: Helm Chart Creation
**Goal**: Package as installable Helm chart

```
helm/
├── Chart.yaml                    # Chart metadata
├── values.yaml                   # Default configuration
├── values.schema.json            # Configuration validation
├── templates/
│   ├── NOTES.txt                # Post-install instructions
│   ├── _helpers.tpl             # Template helpers
│   ├── configmap.yaml           # OAuth2 proxy config
│   ├── secret.yaml              # OAuth credentials
│   ├── gateway.yaml             # Istio gateway
│   ├── sidecar-injector.yaml   # Sidecar template (optional)
│   └── tests/
│       └── test-connection.yaml # Helm test
└── README.md                    # Chart documentation
```

**Key Features**:
- Parameterized domain, namespace, OAuth provider
- Optional Istio gateway (bring-your-own or create new)
- Secret management via values or external secret operators
- Support for multiple OAuth providers
- Configurable sidecar defaults

### Phase 2: Generic Configuration
**Goal**: Remove all hardcoded values

**values.yaml structure**:
```yaml
# Domain configuration
domain: example.com
cookieDomain: .example.com

# OAuth provider
oauth:
  provider: github  # github, google, azure, oidc
  clientID: ""
  clientSecret: ""
  
  # Provider-specific settings
  github:
    org: ""  # Optional org restriction
  
  google:
    hostedDomain: ""  # Optional domain restriction
  
  azure:
    tenant: ""
  
  oidc:
    issuerURL: ""

# Istio configuration
istio:
  enabled: true
  gateway:
    create: true
    name: oauth2-gateway
    existingGateway: ""  # Use existing gateway
    
  ingressGateway:
    name: istio-ingressgateway
    namespace: istio-system

# Sidecar defaults
sidecar:
  image:
    repository: quay.io/oauth2-proxy/oauth2-proxy
    tag: v7.6.0
  resources:
    requests:
      memory: 32Mi
      cpu: 10m
    limits:
      memory: 128Mi
      cpu: 100m
  
  # Default app port (can be overridden per-app)
  upstreamPort: 8080

# Custom templates
customTemplates:
  enabled: true
  logo: ""  # Base64 encoded logo
  brandName: "SSO Portal"
```

### Phase 3: Installation Methods

#### Method A: Helm Install
```bash
# Add repo
helm repo add oauth2-sidecar https://github.com/ianlintner/authproxy/releases/helm-charts

# Install
helm install oauth2-sidecar oauth2-sidecar/oauth2-sidecar \
  --namespace auth --create-namespace \
  --set domain=mycompany.com \
  --set oauth.provider=github \
  --set oauth.clientID=xxxx \
  --set oauth.clientSecret=yyyy
```

#### Method B: Kustomize Remote Base
```bash
# Create kustomization.yaml
cat <<EOF > kustomization.yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
  - github.com/ianlintner/authproxy/k8s/base?ref=v1.0.0

namespace: auth

configMapGenerator:
  - name: oauth2-proxy-config
    behavior: merge
    literals:
      - domain=mycompany.com

secretGenerator:
  - name: oauth2-proxy-secret
    literals:
      - client-id=xxxx
      - client-secret=yyyy
      - cookie-secret=zzzz
EOF

kubectl apply -k .
```

#### Method C: Quick Install Script
```bash
curl -fsSL https://raw.githubusercontent.com/ianlintner/authproxy/main/install.sh | bash
```

### Phase 4: Directory Restructure

```
oauth2-sidecar/
├── README.md                    # Main README
├── LICENSE
├── install.sh                   # One-command installer
│
├── helm/                        # Helm chart
│   └── oauth2-sidecar/
│
├── k8s/                         # Raw manifests
│   ├── base/                    # Reusable base (for kustomize)
│   │   ├── oauth2-proxy-sidecar/
│   │   ├── istio/
│   │   └── kustomization.yaml
│   └── overlays/                # Example overlays
│       ├── github/
│       ├── google/
│       └── azure-ad/
│
├── examples/                    # Complete examples
│   ├── simple-app/              # Basic app with sidecar
│   ├── multi-provider/          # Multiple OAuth providers
│   ├── custom-templates/        # Custom branding
│   └── rbac/                    # With authorization rules
│
├── docs/                        # Documentation
│   ├── README.md
│   ├── architecture.md
│   ├── configuration.md
│   ├── providers/
│   │   ├── github.md
│   │   ├── google.md
│   │   ├── azure-ad.md
│   │   └── oidc.md
│   └── troubleshooting.md
│
└── scripts/                     # Helper scripts
    ├── generate-secret.sh
    ├── add-sidecar.sh
    └── validate.sh
```

### Phase 5: Documentation

#### New README.md Structure:
1. **What is this?** - Clear value proposition
2. **Features** - Key benefits
3. **Quick Start** - 3 commands to get running
4. **Architecture** - Diagram showing flow
5. **Installation** - Helm, Kustomize, Script options
6. **Configuration** - Common scenarios
7. **Examples** - Links to example apps
8. **Troubleshooting** - Common issues
9. **Contributing** - How to contribute
10. **License** - MIT

#### Architecture Diagram:
```
┌─────────────┐
│   Browser   │
└──────┬──────┘
       │ HTTPS
       ▼
┌─────────────────┐
│ Istio Gateway   │
│ *.example.com   │
└────────┬────────┘
         │
         ▼
┌──────────────────────┐
│   Service :4180      │
└──────────┬───────────┘
           │
           ▼
    ┌──────────────┐
    │     Pod      │
    ├──────────────┤
    │ oauth2-proxy │ :4180
    │   (sidecar)  │
    ├──────────────┤
    │      ↓       │
    │   Your App   │ :8080
    └──────────────┘
```

### Phase 6: Example Applications

1. **examples/simple-app/** - Minimal working example
2. **examples/github-org/** - GitHub with org restriction
3. **examples/google-workspace/** - Google Workspace domain
4. **examples/azure-ad/** - Azure AD with tenant
5. **examples/multi-app/** - Multiple apps sharing SSO
6. **examples/custom-branding/** - Custom templates & logo
7. **examples/external-secrets/** - Using External Secrets Operator

## Success Criteria

### User Experience
- [ ] User can deploy in < 5 minutes
- [ ] Works on any Kubernetes cluster with Istio
- [ ] Clear error messages with solutions
- [ ] Comprehensive documentation
- [ ] Multiple working examples

### Technical
- [ ] Helm chart passes lint & test
- [ ] Kustomize remote base works
- [ ] No hardcoded values
- [ ] Supports multiple OAuth providers
- [ ] Optional components (gateway, templates)
- [ ] Resource limits configured
- [ ] Health checks included

### Documentation
- [ ] Architecture diagram
- [ ] Configuration reference
- [ ] Provider-specific guides
- [ ] Troubleshooting guide
- [ ] Migration guide (for existing users)
- [ ] Contributing guide
- [ ] Security best practices

## Timeline

- **Phase 1** (Helm Chart): 2-3 hours
- **Phase 2** (Generic Config): 1-2 hours  
- **Phase 3** (Install Methods): 1-2 hours
- **Phase 4** (Restructure): 1 hour
- **Phase 5** (Documentation): 2-3 hours
- **Phase 6** (Examples): 2-3 hours

**Total**: 9-14 hours

## Next Steps

1. Create Helm chart structure
2. Parameterize all configuration
3. Build install.sh script
4. Restructure directories
5. Write new documentation
6. Create example applications
7. Test on clean cluster
8. Publish to GitHub
9. Create release with Helm chart
10. Write blog post/announcement
