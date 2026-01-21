# Contributing to Kubernetes DNS Auto-Heal

First off, thank you for considering contributing to this project! 🎉

## Table of Contents

- [Code of Conduct](#code-of-conduct)
- [How Can I Contribute?](#how-can-i-contribute)
- [Development Setup](#development-setup)
- [Pull Request Process](#pull-request-process)
- [Coding Standards](#coding-standards)

---

## Code of Conduct

This project adheres to a code of conduct. By participating, you are expected to uphold this code.

### Our Pledge

We pledge to make participation in our project a harassment-free experience for everyone, regardless of age, body size, disability, ethnicity, gender identity and expression, level of experience, nationality, personal appearance, race, religion, or sexual identity and orientation.

### Our Standards

**Positive behavior includes:**
- Using welcoming and inclusive language
- Being respectful of differing viewpoints
- Gracefully accepting constructive criticism
- Focusing on what is best for the community

**Unacceptable behavior includes:**
- Trolling, insulting/derogatory comments, and personal attacks
- Public or private harassment
- Publishing others' private information without permission

---

## How Can I Contribute?

### 🐛 Reporting Bugs

Before creating bug reports, please check existing issues to avoid duplicates.

**When submitting a bug report, include:**
- Clear and descriptive title
- Steps to reproduce the issue
- Expected vs actual behavior
- Kubernetes version, cloud provider (AWS/Azure)
- Relevant logs from pods
- Screenshots if applicable

**Template:**
```markdown
**Describe the bug**
A clear description of what the bug is.

**To Reproduce**
Steps to reproduce:
1. Deploy manifests '...'
2. Run command '...'
3. See error

**Expected behavior**
What you expected to happen.

**Environment:**
- Kubernetes version: [e.g., 1.28]
- Cloud Provider: [AWS EKS / Azure AKS]
- Cluster size: [e.g., 5 nodes]

**Logs:**
```
<paste relevant logs>

### 💡 Suggesting Enhancements

Enhancement suggestions are tracked as GitHub issues.

**When suggesting enhancements, include:**
- Clear and descriptive title
- Detailed description of the proposed feature
- Use case and benefits
- Possible implementation approach

### 📝 Contributing Code

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Make your changes**
4. **Test thoroughly**
5. **Commit with clear messages** (`git commit -m 'Add amazing feature'`)
6. **Push to your fork** (`git push origin feature/amazing-feature`)
7. **Open a Pull Request**

---

## Development Setup

### Prerequisites
```bash
# Required tools
kubectl version --client  # 1.21+
helm version             # 3.0+
docker version           # For testing

# Optional (for local testing)
kind version             # For local Kubernetes cluster
minikube version         # Alternative to kind
```

### Local Development Cluster
```bash
# Create local cluster with kind
kind create cluster --name dns-autoheal-dev

# Or with minikube
minikube start --cpus 4 --memory 8192

# Verify cluster
kubectl cluster-info
```

### Install Development Dependencies
```bash
# Clone your fork
git clone https://github.com/YOUR_USERNAME/kubernetes-dns-autoheal.git
cd kubernetes-dns-autoheal

# Install pre-commit hooks (optional)
pip install pre-commit
pre-commit install

# Make scripts executable
chmod +x scripts/*.sh
```

### Running Tests
```bash
# Validate YAML manifests
kubectl apply --dry-run=client -f manifests/

# Run installation in test mode
./scripts/install.sh

# Verify deployment
./scripts/validate.sh

# Run load tests
./tests/load-test/run-load-test.sh
```

---

## Pull Request Process

### Before Submitting

- [ ] Code follows the project's coding standards
- [ ] Tests pass locally
- [ ] Documentation updated if needed
- [ ] YAML manifests are valid (`kubectl apply --dry-run`)
- [ ] Scripts have proper error handling
- [ ] Commit messages are clear

### PR Template
```markdown
## Description
Brief description of changes

## Type of Change
- [ ] Bug fix
- [ ] New feature
- [ ] Breaking change
- [ ] Documentation update

## Testing
Describe testing performed:
- [ ] Tested on AWS EKS
- [ ] Tested on Azure AKS
- [ ] Load tests passed
- [ ] Alert routing verified

## Checklist
- [ ] Code follows style guidelines
- [ ] Self-review completed
- [ ] Comments added for complex code
- [ ] Documentation updated
- [ ] No new warnings generated
```

### Review Process

1. Maintainers will review within 48 hours
2. Address feedback and push updates
3. Once approved, maintainers will merge
4. Your contribution will be acknowledged in release notes

---

## Coding Standards

### YAML Manifests
```yaml
# Use 2 spaces for indentation
apiVersion: v1
kind: ConfigMap
metadata:
  name: example-config
  namespace: monitoring
  labels:
    app: dns-autoheal
    component: monitoring
data:
  config.yaml: |
    # Inline content uses 4-space indentation
    key: value
```

**Guidelines:**
- Use meaningful resource names
- Always include labels for resource organization
- Add comments for complex configurations
- Use `---` to separate multiple resources in one file

### Bash Scripts
```bash
#!/bin/bash
set -euo pipefail  # Always use strict mode

# Function names use snake_case
check_prerequisites() {
    local required_tool=$1
    
    if ! command -v "$required_tool" &> /dev/null; then
        echo "ERROR: $required_tool not found"
        return 1
    fi
}

# Variables in UPPER_CASE for globals
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Use descriptive variable names
for manifest_file in manifests/*.yaml; do
    kubectl apply -f "$manifest_file"
done
```

**Guidelines:**
- Always use `set -euo pipefail`
- Add error handling for all commands
- Use `shellcheck` to validate scripts
- Include usage/help messages

### Python (for webhook)
```python
#!/usr/bin/env python3
"""
Module docstring explaining purpose
"""
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def scale_coredns(target_replicas: int) -> dict:
    """
    Scale CoreDNS deployment.
    
    Args:
        target_replicas: Desired number of replicas
        
    Returns:
        dict with status and details
    """
    try:
        # Implementation
        logger.info(f"Scaling CoreDNS to {target_replicas} replicas")
        return {"status": "success"}
    except Exception as e:
        logger.error(f"Failed to scale: {e}")
        return {"status": "error", "message": str(e)}
```

**Guidelines:**
- Follow PEP 8 style guide
- Use type hints
- Add docstrings for all functions
- Use logging instead of print

### Documentation

**Markdown files:**
- Use clear headings (H1 for title, H2 for sections)
- Include code blocks with language specification
- Add screenshots/diagrams where helpful
- Keep line length reasonable (80-100 chars)

**Comments in code:**
- Explain *why*, not *what*
- Update comments when code changes
- Use TODO/FIXME/NOTE tags appropriately

---

## Project Structure Guidelines

### Adding New Manifests

Place manifests in appropriate directories:
---
manifests/
├── 01-namespace/        # Namespace definitions
├── 02-monitoring/       # Monitoring components
├── 03-prometheus-grafana/  # Observability
├── 04-autoscaling/      # Auto-scaling configs
├── 05-remediation/      # Remediation logic
└── 06-alerting/         # Alert configurations

### Adding New Scripts
---
scripts/
├── install.sh           # Main installer
├── validate.sh          # Validation
├── test-*.sh           # Test scripts
└── monitoring/         # Platform-specific scripts

### Adding Documentation
---
docs/
├── architecture.md      # Architecture details
├── implementation-guide.md  # Step-by-step guide
├── troubleshooting.md   # Common issues
└── images/             # Diagrams and screenshots


---

## Testing Requirements

### For New Features

- [ ] Unit tests (if applicable)
- [ ] Integration tests
- [ ] Load tests (for performance-critical features)
- [ ] Documentation updated
- [ ] Example configuration added

### For Bug Fixes

- [ ] Test case demonstrating the bug
- [ ] Fix verified with test
- [ ] Regression test added
- [ ] Related documentation updated

---

## Release Process

Maintainers will:

1. Update version in relevant files
2. Update CHANGELOG.md
3. Create GitHub release with notes
4. Tag release (`git tag v1.x.x`)
5. Publish updated Helm chart (if applicable)

---

## Questions?

- 💬 Open a [Discussion](https://github.com/bharathvasudevanmsuk11/kubernetes-dns-autoheal/discussions)
- 📧 Email: coming soon
- 💼 LinkedIn: [Bharath Vasudevan](https://www.linkedin.com/in/bharath-vasudevan-b4b07315/)

---

## Recognition

Contributors will be:
- Listed in release notes
- Mentioned in README acknowledgements
- Added to CONTRIBUTORS.md file

Thank you for contributing! 🙏
