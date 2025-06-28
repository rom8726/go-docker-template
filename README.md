# Go Docker Template

Reusable template for Go projects with Docker, including:

- 🐳 Docker with scratch image support
- 🔒 Automatic security testing
- 🛠️ Development tools (lint, test, mocks)
- 📦 Dependency management
- 🎯 Beautiful help with parsing

## Quick Start

1. Configure variables in Makefile:
```makefile
# Change these variables for your project
PROJECT_NAME=your-project-name
DOCKER_REGISTRY=your-registry.com
VERSION_PKG=github.com/your-org/your-project/internal/version
```

3. Run setup:
```bash
make setup
```

## Main Commands

```bash
make help                    # Show all available commands
make setup                   # Setup development environment
make build                   # Build binary
make test                    # Run unit tests
make test.integration        # Run integration tests
make lint                    # Code linting
make mocks                   # Generate mocks
make docker-build            # Build Docker image
make test.security           # Security tests
make test.certificates       # Certificate tests
```

## Features

### 🔒 Security
- Automatic scratch image detection
- Docker container security testing
- SSL/TLS certificate testing

### 🐳 Docker
- Scratch image support for minimal size
- Automatic CA certificate copying
- Optimized multi-stage builds

### 🛠️ Development
- golangci-lint for code checking
- mockery for mock generation
- tparse for beautiful test output
- Automatic tool installation

### 📊 Testing
- Unit and integration tests
- Code coverage
- HTML coverage reports

## File Structure

```
.
├── Makefile                 # Main Makefile
├── dev/
│   └── dev.mk              # Additional development commands
└── scripts/
    ├── test-security.sh    # Security tests
    └── test-certificates.sh # Certificate tests
```

## Configuration

### Makefile Variables

Main variables for configuration:

```makefile
PROJECT_NAME=your-project-name          # Project name
DOCKER_REGISTRY=your-registry.com       # Docker registry
VERSION_PKG=github.com/your-org/your-project/internal/version  # Version package
BIN_OUTPUT_DIR=bin                      # Binary output directory
IGNORE_TEST_DIRS=cmd,test_mocks         # Directories to exclude from tests
```

### Docker

Template supports both regular Linux images and scratch images. Automatically detects image type and adapts security tests.

### Security

Security scripts check:
- Shell/bash access
- Environment variable leaks
- Arbitrary command execution
- Root user execution (for regular images)
- Sensitive files presence
- CA certificates

## License

Apache-2.0 License
