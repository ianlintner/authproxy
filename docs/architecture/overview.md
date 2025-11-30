# Architecture Overview

Understanding the OAuth2 Sidecar Proxy architecture and design decisions.

## Design Philosophy

The OAuth2 Sidecar Proxy is built on three core principles:

1. **Simplicity**: Avoid complex centralized authentication services
2. **Isolation**: Each application manages its own authentication lifecycle
3. **Portability**: Applications can easily move between clusters

## High-Level Architecture

```mermaid
graph TB
    subgraph Internet
        A[Users]
    end
    
    subgraph Azure Load Balancer
        B[Public IP]
    end
    
    subgraph Istio Ingress
        C[Gateway<br/>*.example.com]
        D[VirtualService]
    end
    
    subgraph Kubernetes Cluster
        E[Service<br/>:4180]
        
        subgraph Pod
            F[oauth2-proxy<br/>:4180]
            G[Application<br/>:8080]
        end
    end
    
    subgraph OAuth Provider
        H[GitHub/Google/<br/>Azure AD]
    end
    
    A -->|HTTPS| B
    B --> C
    C --> D
    D --> E
    E --> F
    F -->|localhost| G
    F -.->|OAuth Flow| H
    
    style F fill:#4c51bf,stroke:#333,stroke-width:3px,color:#fff
    style G fill:#10b981,stroke:#333,stroke-width:2px,color:#fff
    style H fill:#f59e0b,stroke:#333,stroke-width:2px,color:#fff
```

## Components

### 1. Istio Ingress Gateway

The entry point for all external traffic to your cluster.

**Responsibilities:**
- TLS termination using wildcard certificate
- HTTP to HTTPS redirect
- Route traffic to application services based on hostname

**Key Configuration:**
```yaml
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: oauth2-gateway
spec:
  selector:
    istio: ingressgateway
  servers:
  - port:
      number: 443
      name: https
      protocol: HTTPS
    tls:
      mode: SIMPLE
      credentialName: wildcard-tls
    hosts:
    - "*.example.com"
```

### 2. VirtualService

Routes traffic from the Gateway to your application service.

**Responsibilities:**
- Host-based routing (e.g., `app1.example.com` → `app1-service`)
- Directs traffic to port 4180 (oauth2-proxy)

```mermaid
graph LR
    A[Gateway] --> B{VirtualService}
    B -->|app1.example.com| C[app1-service:4180]
    B -->|app2.example.com| D[app2-service:4180]
    B -->|app3.example.com| E[app3-service:4180]
    
    style B fill:#4c51bf,stroke:#333,stroke-width:2px,color:#fff
```

### 3. Service

Kubernetes service that exposes the oauth2-proxy port.

**Key Points:**
- Exposes port 4180 (not your app's port!)
- Type: ClusterIP (internal only)
- Routes to pods with matching labels

### 4. Pod with Sidecar

The core of the architecture: a pod containing both oauth2-proxy and your application.

```mermaid
graph TB
    subgraph Pod
        direction TB
        A[Service Traffic<br/>:4180] --> B[oauth2-proxy container<br/>:4180]
        B -->|Check Session| C{Authenticated?}
        C -->|No| D[Redirect to<br/>OAuth Provider]
        C -->|Yes| E[Proxy Request]
        E --> F[Application<br/>container<br/>:8080]
        F --> G[Response]
        G --> B
        B --> H[Back to Client]
    end
    
    D -.->|OAuth Flow| I[GitHub/Google/etc]
    I -.->|Callback| B
    
    style B fill:#4c51bf,stroke:#333,stroke-width:2px,color:#fff
    style F fill:#10b981,stroke:#333,stroke-width:2px,color:#fff
    style I fill:#f59e0b,stroke:#333,stroke-width:2px,color:#fff
```

**Container Details:**

=== "oauth2-proxy Sidecar"

    ```yaml
    - name: oauth2-proxy
      image: quay.io/oauth2-proxy/oauth2-proxy:v7.6.0
      ports:
      - containerPort: 4180
      env:
      - name: OAUTH2_PROXY_REDIRECT_URL
        value: "https://auth.example.com/oauth2/callback"
      - name: OAUTH2_PROXY_UPSTREAMS
        value: "http://127.0.0.1:8080"
      - name: OAUTH2_PROXY_CLIENT_ID
        valueFrom:
          secretKeyRef:
            name: oauth2-proxy-secret
            key: client-id
      # ... more config
    ```

=== "Application Container"

    ```yaml
    - name: app
      image: your-app:latest
      ports:
      - containerPort: 8080
      # Your app listens on 8080
      # Receives authenticated requests from oauth2-proxy
      # Gets user info via headers
    ```

### 5. Configuration

Two main configuration sources:

**ConfigMap** - OAuth2 proxy settings:
```yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: oauth2-proxy-sidecar-config
data:
  oauth2_proxy.cfg: |
    provider = "github"
    cookie_domains = [".example.com"]
    skip_provider_button = false
    custom_templates_dir = "/templates"
    # ... more settings
```

**Secret** - Sensitive OAuth credentials:
```yaml
apiVersion: v1
kind: Secret
metadata:
  name: oauth2-proxy-secret
type: Opaque
data:
  client-id: <base64>
  client-secret: <base64>
  cookie-secret: <base64>
```

## Authentication Flow

### First Visit (Not Authenticated)

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant Istio
    participant Sidecar as oauth2-proxy
    participant App
    participant Provider as OAuth Provider

    User->>Istio: GET https://app.example.com/
    Istio->>Sidecar: Forward request
    Sidecar->>Sidecar: Check for session cookie
    Note over Sidecar: No valid cookie found
    Sidecar-->>User: 200 OK (Sign-in page HTML)
    User->>Sidecar: Click provider button
    Sidecar-->>User: 302 Redirect to OAuth provider
    User->>Provider: GET /authorize?client_id=...
    Provider-->>User: Login page
    User->>Provider: Submit credentials
    Provider-->>User: 302 Redirect /oauth2/callback?code=...
    User->>Sidecar: GET /oauth2/callback?code=...
    Sidecar->>Provider: POST /token (exchange code)
    Provider-->>Sidecar: Access token + user info
    Sidecar->>Sidecar: Create session
    Sidecar-->>User: 302 Set-Cookie + Redirect to /
    User->>Sidecar: GET / (with cookie)
    Sidecar->>Sidecar: Validate cookie
    Sidecar->>App: Proxy request + inject headers
    App-->>Sidecar: Response
    Sidecar-->>User: Response
```

### Subsequent Visits (Authenticated)

```mermaid
sequenceDiagram
    autonumber
    participant User
    participant Istio
    participant Sidecar as oauth2-proxy
    participant App

    User->>Istio: GET / (with cookie)
    Istio->>Sidecar: Forward request
    Sidecar->>Sidecar: Validate session cookie
    Note over Sidecar: Cookie valid!
    Sidecar->>App: Proxy to localhost:8080<br/>+ inject user headers
    Note over App: X-Auth-Request-Email<br/>X-Auth-Request-User<br/>...
    App-->>Sidecar: Response
    Sidecar-->>User: Response
```

## Single Sign-On (SSO)

SSO works by sharing the session cookie across all applications in your domain.

```mermaid
graph TB
    subgraph Domain: .example.com
        A[app1.example.com]
        B[app2.example.com]
        C[app3.example.com]
    end
    
    D[Shared Cookie<br/>_oauth2_proxy<br/>Domain: .example.com]
    
    D -.->|Used by| A
    D -.->|Used by| B
    D -.->|Used by| C
    
    E[User logs in once] --> D
    
    style D fill:#4c51bf,stroke:#333,stroke-width:2px,color:#fff
    style E fill:#10b981,stroke:#333,stroke-width:2px,color:#fff
```

**How it works:**

1. User authenticates to `app1.example.com`
2. Cookie is set with domain `.example.com`
3. User visits `app2.example.com`
4. Browser automatically sends the cookie
5. `app2` validates the cookie ✓
6. User is already authenticated!

## Design Decisions

### Why Sidecar vs. Centralized?

| Aspect | Sidecar Pattern | Centralized Service |
|--------|----------------|---------------------|
| **Configuration** | Simple per-app config | Complex ext_authz setup |
| **Debugging** | Easy - logs with app | Hard - distributed logs |
| **Isolation** | Each app independent | Shared state/failures |
| **Flexibility** | Different providers per app | One provider for all |
| **Portability** | Move apps easily | Tied to infrastructure |
| **Overhead** | ~50MB per app | Single deployment |

!!! success "Sidecar Benefits"
    - **Simpler**: No Istio ext_authz filter needed
    - **More reliable**: No single point of failure
    - **Easier to debug**: Auth logs are with your app
    - **More flexible**: Each app can use different OAuth providers

!!! warning "Centralized Benefits"
    - **Lower resource usage**: One oauth2-proxy for all apps
    - **Centralized management**: Single place to update auth config

For most use cases, the sidecar pattern's benefits outweigh the small resource overhead.

### Why Not Service Mesh mTLS?

Service mesh mTLS provides **service-to-service** authentication but doesn't handle **end-user** authentication. You need both:

- **mTLS**: Encrypts and authenticates service communication
- **OAuth2**: Authenticates end users and provides identity

They complement each other!

### Cookie-Based Sessions

We use cookie-based sessions (not JWT or database-backed sessions) because:

- ✅ **Fast**: No database lookup on every request
- ✅ **Scalable**: Stateless, works with any replica
- ✅ **Simple**: No session store to manage
- ✅ **Secure**: Encrypted, httpOnly, secure flags

The cookie is encrypted with the `cookie-secret`, so even if intercepted, it cannot be read or modified.

## Security Considerations

See the [Security Model](security.md) page for detailed security information.

## Next Steps

- [Learn about the sidecar pattern](sidecar-pattern.md)
- [Understand traffic flow](traffic-flow.md)
- [Review security model](security.md)
