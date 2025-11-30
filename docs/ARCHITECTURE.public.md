# OAuth2 Sidecar Architecture (Public)

This document describes the architecture of the OAuth2 Sidecar solution for Kubernetes.

## Overview

The solution uses the sidecar pattern with `oauth2-proxy` and Istio to provide authentication for any HTTP application without code changes.

Key components:
- Istio Gateway for TLS termination and routing
- Kubernetes Service routing to oauth2-proxy sidecar
- Pod with two containers: your app and oauth2-proxy
- OAuth2 provider (GitHub, Google, Azure AD, OIDC)

See the main README for diagrams and flow.
