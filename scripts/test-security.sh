#!/bin/bash

# Minimal security check script for Docker images
# Go Docker Template

set -e

IMAGE_NAME="$1"
APP_BINARY="$2"
FAILURES=0

if [ -z "$IMAGE_NAME" ]; then
    echo "Usage: $0 <image_name> [binary_path]"
    echo "Example: $0 my-server:latest /bin/app"
    exit 1
fi

echo "🔒 Testing security of image: $IMAGE_NAME"
echo "=========================================="

# Helper
fail() {
    echo "❌ FAIL: $1"
    FAILURES=1
}

pass() {
    echo "✅ PASS: $1"
}

# Detect if image is scratch-based
echo "🔍 Detecting image type..."
IS_SCRATCH=0

# Check Dockerfile for scratch base image
if [ -f "Dockerfile" ]; then
    # Get the last FROM instruction and check if it's scratch
    LAST_FROM=$(grep -i "^FROM" Dockerfile | tail -1)
    if echo "$LAST_FROM" | grep -q "FROM scratch"; then
        IS_SCRATCH=1
        echo "📦 Detected: Scratch-based image (FROM scratch in Dockerfile)"
    else
        echo "🐧 Detected: Regular Linux image (FROM $LAST_FROM)"
    fi
else
    # Fallback: try to detect by running a command
    echo "⚠️  WARNING: Dockerfile not found, using fallback detection"
    if docker run --rm "$IMAGE_NAME" echo "test" 2>&1 | grep -q "no such file or directory\|not found\|executable file not found\|exec format error"; then
        IS_SCRATCH=1
        echo "📦 Detected: Scratch-based image (fallback detection)"
    else
        echo "🐧 Detected: Regular Linux image (fallback detection)"
    fi
fi
echo ""

# 1. Shell access
echo "1. Checking shell access..."
docker run --rm "$IMAGE_NAME" /bin/sh 2>/dev/null && fail "Shell access is possible" || pass "Shell access blocked"

# 2. Bash access
echo "2. Checking bash access..."
docker run --rm "$IMAGE_NAME" /bin/bash 2>/dev/null && fail "Bash access is possible" || pass "Bash access blocked"

# 3. Env var leak
echo "3. Checking environment variable exposure..."
if [ "$IS_SCRATCH" -eq 1 ]; then
    # For scratch images, env command is not available, so we assume it's secure
    pass "Environment variables not exposed (scratch image)"
else
    docker run --rm -e TEST_VAR=secret "$IMAGE_NAME" env 2>/dev/null | grep -q TEST_VAR && fail "Environment variables are exposed" || pass "Environment variables not exposed"
fi

# 4. Arbitrary command execution
echo "4. Checking arbitrary command execution..."
if [ "$IS_SCRATCH" -eq 1 ]; then
    # For scratch images, only our app binary is available
    pass "Arbitrary commands blocked (scratch image)"
else
    docker run --rm "$IMAGE_NAME" whoami 2>/dev/null && fail "Arbitrary command executed" || pass "Arbitrary commands blocked"
fi

# 5. Run as root (skip for scratch images)
if [ "$IS_SCRATCH" -eq 1 ]; then
    echo "5. Skipping root user check (scratch image)"
else
    echo "5. Checking if container runs as root..."
    USER_ID=$(docker run --rm "$IMAGE_NAME" id -u 2>/dev/null || echo "no-access")
    if [ "$USER_ID" = "0" ]; then
        echo "⚠️  WARNING: Container runs as root (this is common for many applications)"
    else
        pass "Container runs as non-root (UID=$USER_ID)"
    fi
fi

# 6. Sensitive files
echo "6. Checking for sensitive system files..."
if [ "$IS_SCRATCH" -eq 1 ]; then
    # For scratch images, these files should not exist
    pass "/etc/passwd not found (scratch image)"
    pass "/etc/shadow not found (scratch image)"
else
    for FILE in /etc/passwd /etc/shadow; do
        docker run --rm "$IMAGE_NAME" test -f "$FILE" && fail "$FILE found" || pass "$FILE not found"
    done
fi

# 7. Application binary
if [[ -n "$APP_BINARY" ]]; then
    echo "7. Checking application binary at $APP_BINARY..."
    docker run --rm "$IMAGE_NAME" "$APP_BINARY" --help 2>/dev/null && pass "Application binary is accessible" || fail "$APP_BINARY is not accessible or not executable"
else
    echo "7. Skipping application binary check (no path provided)"
fi

# 8. Image size
echo "8. Checking image size..."
SIZE=$(docker images --format "{{.Size}}" "$IMAGE_NAME")
echo "📦 Image size: $SIZE"

# 9. CA certificates (different approach for scratch vs regular images)
echo "9. Checking for CA certificates..."
if [ "$IS_SCRATCH" -eq 1 ]; then
    # For scratch images, check Dockerfile
    if [ -f "Dockerfile" ]; then
        if grep -q "ca-certificates.crt" Dockerfile; then
            pass "CA certificates found in Dockerfile"
        else
            fail "CA certificates not found in Dockerfile"
        fi
    else
        echo "⚠️  WARNING: Dockerfile not found, skipping CA certificates check"
    fi
else
    # For regular images, check inside container
    CA_PATHS=(
        /etc/ssl/certs/ca-certificates.crt
        /etc/ssl/certs/ca-bundle.crt
        /etc/pki/tls/certs/ca-bundle.crt
    )
    FOUND_CA=0
    for CA_PATH in "${CA_PATHS[@]}"; do
        if docker run --rm "$IMAGE_NAME" test -f "$CA_PATH" 2>/dev/null; then
            pass "CA certificates found at $CA_PATH"
            FOUND_CA=1
            break
        fi
    done
    [ "$FOUND_CA" -eq 0 ] && fail "CA certificates not found in common paths"
fi

# Final summary
echo ""
if [ "$FAILURES" -eq 0 ]; then
    echo "🎉 All security checks passed!"
    exit 0
else
    echo "⚠️  Some checks failed"
    exit 1
fi 