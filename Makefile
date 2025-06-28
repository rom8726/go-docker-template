# Go Docker Template Makefile
# Configure the variables below for your project

# =============================================================================
# PROJECT CONFIGURATION
# =============================================================================

# Basic project settings
PROJECT_NAME ?= your-project-name
DOCKER_REGISTRY ?= your-registry.com
VERSION_PKG ?= github.com/your-org/your-project/internal/version
BIN_OUTPUT_DIR ?= bin
IGNORE_TEST_DIRS ?= cmd,test_mocks,specs,scripts,migrations,docs,dev,internal/generated,tests

# Tool versions
GOCI_VERSION ?= v1.64.8
MOCKERY_VERSION ?= v2.53.3

# =============================================================================
# INTERNAL VARIABLES
# =============================================================================

TOOLS_DIR=dev/tools
TOOLS_DIR_ABS=${PWD}/${TOOLS_DIR}
GOLANGCI_LINT=${TOOLS_DIR}/golangci-lint
MOCKERY=${TOOLS_DIR}/mockery
TPARSE=${TOOLS_DIR}/tparse
GOCMD=go
GOBUILD=$(GOCMD) build
GOPROXY=https://proxy.golang.org,direct
TOOL_VERSION ?= $(shell git describe --tags 2>/dev/null || git rev-parse --short HEAD)
TOOL_BUILD_TIME=$(shell date '+%Y-%m-%dT%H:%M:%SZ%Z')
OS=$(shell uname -s)

# LD Flags for build
LD_FLAGS="-w -s -X '$(VERSION_PKG).Version=${TOOL_VERSION}' -X '$(VERSION_PKG).BuildTime=${TOOL_BUILD_TIME}'"

# Colors for output
RED="\033[0;31m"
GREEN="\033[1;32m"
YELLOW="\033[0;33m"
NOCOLOR="\033[0m"

.DEFAULT_GOAL := help

# =============================================================================
# EXTRA TARGETS
# =============================================================================

-include dev/dev.mk

# =============================================================================
# MAIN TARGETS
# =============================================================================

.PHONY: help
help: ## Show all available commands
	@echo "$$(grep -hE '^\S+:.*##' $(MAKEFILE_LIST) | sed -e 's/:.*##\s*/:/' -e 's/^\(.\+\):\(.*\)/\\x1b[36m\1\\x1b[m:\2/' | column -c2 -t -s :)"

# =============================================================================
# TOOL INSTALLATION
# =============================================================================

.PHONY: .install-linter
.install-linter:
	@[ -f $(GOLANGCI_LINT) ] || curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(TOOLS_DIR) $(GOCI_VERSION)

.PHONY: .install-mockery
.install-mockery:
	@[ -f $(MOCKERY) ] || GOBIN=$(TOOLS_DIR_ABS) go install github.com/vektra/mockery/v2@$(MOCKERY_VERSION)

.PHONY: .install_tparse
.install_tparse:
	@[ -f $(TPARSE) ] || GOBIN=$(TOOLS_DIR_ABS) go install github.com/mfridman/tparse@latest

# =============================================================================
# ENVIRONMENT SETUP
# =============================================================================

.PHONY: setup
setup: .install-linter .install-mockery .install_tparse ## Setup development environment
	@echo "\nCreating .env files in dev/ directory"
	@if [ -f "dev/config.env.example" ]; then \
		cp dev/config.env.example dev/config.env; \
		echo "   ✅ dev/config.env created"; \
	else \
		echo "   ⚠️  dev/config.env.example not found"; \
	fi
	@if [ -f "dev/compose.env.example" ]; then \
		cp dev/compose.env.example dev/compose.env; \
		echo "   ✅ dev/compose.env created"; \
	else \
		echo "   ⚠️  dev/compose.env.example not found"; \
	fi

	@echo
	@if [ $$? -ne 0 ] ; then \
		@echo -e ${RED}"FAIL"${NOCOLOR} ; \
		exit 1 ; \
	fi
	@echo ${GREEN}"OK"${NOCOLOR}

# =============================================================================
# CODE QUALITY
# =============================================================================

.PHONY: lint
lint: .install-linter ## Run linter
	@$(GOLANGCI_LINT) run ./... --config=./.golangci.yml

.PHONY: format
format: ## Format Go code
	go fmt ./...

# =============================================================================
# TESTING
# =============================================================================

.PHONY: test
test: .install_tparse ## Run unit tests
	@IGNORE_PATTERN="$$(echo $(IGNORE_TEST_DIRS) | tr ',' '|')" ; \
	PKGS="$$(go list ./... | grep -Ev "/($$IGNORE_PATTERN)(/|$$)")" ; \
	go test -json -cover -coverprofile=coverage.out -v $$PKGS > test.out || true
	@go tool cover -html=coverage.out -o coverage.html
	@$(TPARSE) -all -file=test.out

.PHONY: test.integration
test.integration: .install_tparse ## Run unit and integration tests
	@IGNORE_PATTERN="$$(echo $(IGNORE_TEST_DIRS) | tr ',' '|')" ; \
	PKGS="$$(go list -tags=integration ./... | grep -Ev "/($$IGNORE_PATTERN)(/|$$)")" ; \
	go test -tags=integration -json -cover -coverprofile=coverage.out -v $$PKGS > test.out || true
	@go tool cover -html=coverage.out -o coverage.html
	@$(TPARSE) -all -file=test.out

# =============================================================================
# BUILD
# =============================================================================

.PHONY: build
build: ## Build binary
	@echo "\nBuilding binary..."
	@echo
	go env -w GOPROXY=${GOPROXY}
	go env -w GOPRIVATE=${GOPRIVATE}

	CGO_ENABLED=0 $(GOBUILD) -trimpath -ldflags=$(LD_FLAGS) -o ${BIN_OUTPUT_DIR}/app .

# =============================================================================
# CODE GENERATION
# =============================================================================

.PHONY: mocks
mocks: .install-mockery ## Generate mocks with mockery
	./dev/tools/mockery

.PHONY: generate-server
generate-server: ## Generate server from OpenAPI specification
	@docker run --rm \
      --volume ".:/workspace" \
      ghcr.io/ogen-go/ogen:latest --target workspace/internal/generated/server --clean workspace/specs/server.yml

# =============================================================================
# DOCKER
# =============================================================================

.PHONY: docker-build
docker-build: ## Build Docker image
	@echo "\nBuilding Docker image..."
	@docker build -t $(PROJECT_NAME):latest -f ./Dockerfile .
	@if [ $$? -ne 0 ] ; then \
		@echo -e ${RED}"FAIL"${NOCOLOR} ; \
		exit 1 ; \
	fi
	@echo ${GREEN}"Docker image '$(PROJECT_NAME)' built successfully!"${NOCOLOR}

.PHONY: docker-push
docker-push: docker-build ## Tag and push Docker image
	@echo "\nTagging Docker image..."
	@docker tag $(PROJECT_NAME):latest $(DOCKER_REGISTRY)/$(PROJECT_NAME):latest
	@if [ $$? -ne 0 ] ; then \
		@echo -e ${RED}"Tagging FAILED"${NOCOLOR} ; \
		exit 1 ; \
	fi

	@echo "\nPushing Docker image to registry..."
	@docker push $(DOCKER_REGISTRY)/$(PROJECT_NAME):latest
	@if [ $$? -ne 0 ] ; then \
		@echo -e ${RED}"Push FAILED"${NOCOLOR} ; \
		exit 1 ; \
	fi
	@echo ${GREEN}"\nDocker image pushed to registry successfully!"${NOCOLOR}

# =============================================================================
# SECURITY TESTS
# =============================================================================

.PHONY: test.security
test.security: ## Run security tests
	@echo "\nRunning security tests..."
	@chmod +x scripts/test-security.sh
	@./scripts/test-security.sh $(PROJECT_NAME)
	@if [ $$? -ne 0 ] ; then \
		@echo -e ${RED}"Security tests FAILED"${NOCOLOR} ; \
		exit 1 ; \
	fi
	@echo ${GREEN}"Security tests passed!"${NOCOLOR}

.PHONY: test.certificates
test.certificates: ## Test certificates in container
	@echo "\nTesting certificates in container..."
	@./scripts/test-certificates.sh

# =============================================================================
# CLEANUP
# =============================================================================

.PHONY: clean
clean: ## Clean temporary files
	@echo "Cleaning temporary files..."
	@rm -rf $(BIN_OUTPUT_DIR)
	@rm -f coverage.out coverage.html test.out
	@echo ${GREEN}"Cleanup completed"${NOCOLOR}

.PHONY: clean-tools
clean-tools: ## Clean installed tools
	@echo "Cleaning tools..."
	@rm -rf $(TOOLS_DIR)
	@echo ${GREEN}"Tools removed"${NOCOLOR} 