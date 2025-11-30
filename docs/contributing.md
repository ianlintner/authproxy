# Contributing to OAuth2 Sidecar Proxy

Thank you for your interest in contributing! This document provides guidelines for contributing to the project.

## Code of Conduct

Be respectful and inclusive. We welcome contributions from everyone.

## How to Contribute

### Reporting Bugs

1. Check if the bug is already reported in [Issues](https://github.com/ianlintner/authproxy/issues)
2. If not, create a new issue with:
   - Clear title and description
   - Steps to reproduce
   - Expected vs actual behavior
   - Environment details (K8s version, Istio version, etc.)
   - Relevant logs

### Suggesting Enhancements

1. Check existing [Issues](https://github.com/ianlintner/authproxy/issues) and [Discussions](https://github.com/ianlintner/authproxy/discussions)
2. Create a new discussion or issue describing:
   - The problem you're trying to solve
   - Your proposed solution
   - Any alternatives you've considered

### Pull Requests

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Test your changes thoroughly
5. Update documentation if needed
6. Commit with clear messages
7. Push to your fork
8. Open a Pull Request

#### PR Guidelines

- Follow existing code style
- Include tests if adding features
- Update documentation
- Keep PRs focused - one feature/fix per PR
- Reference related issues

## Development Setup

### Prerequisites

- Kubernetes cluster (kind, minikube, or cloud)
- kubectl
- Helm 3
- Docker

### Local Development

```bash
# Clone the repo
git clone https://github.com/ianlintner/authproxy.git
cd authproxy

# Install MkDocs for documentation
pip install -r docs/requirements.txt

# Serve documentation locally
mkdocs serve

# Test Kubernetes manifests
./scripts/validate.sh
```

### Documentation

We use MkDocs with Material theme. Documentation is in the `docs/` directory.

```bash
# Install dependencies
pip install -r docs/requirements.txt

# Serve locally
mkdocs serve

# Build
mkdocs build
```

#### Documentation Guidelines

- Use clear, concise language
- Include code examples
- Add Mermaid diagrams for complex concepts
- Test all commands and examples
- Use admonitions for important notes

### Testing

Before submitting a PR:

```bash
# Validate Kubernetes manifests
kubectl apply --dry-run=client -k k8s/base/
kubectl apply --dry-run=client -k k8s/apps/example-app/

# Test Helm chart
helm lint helm/oauth2-sidecar/
helm template oauth2-sidecar helm/oauth2-sidecar/ --values examples/simple-app/values.yaml

# Run validation script
./scripts/validate.sh
```

### Helm Chart Development

When modifying the Helm chart:

1. Update version in `Chart.yaml`
2. Update `values.yaml` with new options
3. Document changes in chart README
4. Test with different value combinations
5. Run `helm lint`

## Project Structure

```
├── docs/                   # MkDocs documentation
├── helm/oauth2-sidecar/   # Helm chart
├── k8s/                   # Kubernetes manifests
│   ├── base/             # Base resources
│   └── apps/             # Example apps
├── scripts/              # Helper scripts
└── examples/             # Example configurations
```

## Commit Message Guidelines

Use clear, descriptive commit messages:

```
type(scope): brief description

Detailed explanation of what changed and why.

Fixes #123
```

**Types:**
- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `style`: Code style changes (formatting)
- `refactor`: Code refactoring
- `test`: Adding tests
- `chore`: Maintenance tasks

**Examples:**
```
feat(helm): add support for custom OAuth scopes
fix(sidecar): correct redirect URL environment variable
docs(quickstart): add Google OAuth setup instructions
```

## Release Process

Maintainers will:

1. Update version in relevant files
2. Update CHANGELOG
3. Create git tag
4. Build and push Helm chart
5. Update documentation
6. Create GitHub release

## Questions?

- **Discussions**: [GitHub Discussions](https://github.com/ianlintner/authproxy/discussions)
- **Issues**: [GitHub Issues](https://github.com/ianlintner/authproxy/issues)

## License

By contributing, you agree that your contributions will be licensed under the MIT License.
