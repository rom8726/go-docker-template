#!/bin/bash

# Test certificates in container script
# Go Docker Template

set -e

echo "🔍 Testing certificates in container..."

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

CONTAINER_NAME=${1:-"your-project-name"}

echo "📦 Testing container: $CONTAINER_NAME"

# Check if container exists
if ! docker ps --format "table {{.Names}}" | grep -q "^${CONTAINER_NAME}$"; then
    echo -e "${RED}❌ Container $CONTAINER_NAME is not running${NC}"
    exit 1
fi

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
    if docker exec "$CONTAINER_NAME" echo "test" 2>&1 | grep -q "no such file or directory\|not found\|executable file not found\|exec format error"; then
        IS_SCRATCH=1
        echo "📦 Detected: Scratch-based image (fallback detection)"
    else
        echo "🐧 Detected: Regular Linux image (fallback detection)"
    fi
fi
echo ""

echo "🔐 Checking certificate files..."

if [ "$IS_SCRATCH" -eq 1 ]; then
    # For scratch images, check if application is accessible
    if docker exec "$CONTAINER_NAME" /bin/app --help >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Application binary is accessible${NC}"
        echo -e "${GREEN}✅ CA certificates should be available at /etc/ssl/certs/ca-certificates.crt${NC}"
        echo "   (copied from Dockerfile)"
    else
        echo -e "${RED}❌ Application binary is not accessible${NC}"
    fi
else
    # For regular images, check if CA certificates file exists
    if docker exec "$CONTAINER_NAME" test -f /etc/ssl/certs/ca-certificates.crt; then
        echo -e "${GREEN}✅ CA certificates file exists${NC}"
        
        # Check file size
        size=$(docker exec "$CONTAINER_NAME" stat -c%s /etc/ssl/certs/ca-certificates.crt 2>/dev/null || echo "0")
        echo "   File size: $size bytes"
        
        if [ "$size" -gt 0 ]; then
            echo -e "${GREEN}✅ CA certificates file is not empty${NC}"
        else
            echo -e "${RED}❌ CA certificates file is empty${NC}"
        fi
    else
        echo -e "${RED}❌ CA certificates file does not exist${NC}"
    fi
fi

echo ""
echo "🌐 Testing SSL/TLS connections..."

# Test HTTPS connection to a known site
if docker exec "$CONTAINER_NAME" curl -s --connect-timeout 10 https://www.google.com >/dev/null 2>&1; then
    echo -e "${GREEN}✅ HTTPS connection to Google works${NC}"
else
    echo -e "${RED}❌ HTTPS connection to Google fails${NC}"
fi

# Test HTTPS connection to GitHub
if docker exec "$CONTAINER_NAME" curl -s --connect-timeout 10 https://api.github.com >/dev/null 2>&1; then
    echo -e "${GREEN}✅ HTTPS connection to GitHub works${NC}"
else
    echo -e "${RED}❌ HTTPS connection to GitHub fails${NC}"
fi

echo ""
echo "📧 Testing SMTP TLS connections..."

if [ "$IS_SCRATCH" -eq 1 ]; then
    # For scratch images, use curl for SMTP test
    if docker exec "$CONTAINER_NAME" curl -s --connect-timeout 10 --max-time 10 smtp://smtp.gmail.com:587 >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SMTP connection test works${NC}"
    else
        echo -e "${YELLOW}⚠️  SMTP connection test failed (this might be expected)${NC}"
    fi
else
    # For regular images, use openssl for SMTP STARTTLS
    if docker exec "$CONTAINER_NAME" timeout 10 bash -c 'echo "QUIT" | openssl s_client -connect smtp.gmail.com:587 -starttls smtp -crlf' >/dev/null 2>&1; then
        echo -e "${GREEN}✅ SMTP STARTTLS connection test works${NC}"
    else
        echo -e "${YELLOW}⚠️  SMTP STARTTLS connection test failed (this might be expected)${NC}"
    fi
fi

echo ""
echo "🔍 Checking tools availability..."

if [ "$IS_SCRATCH" -eq 1 ]; then
    # For scratch images, check curl
    if docker exec "$CONTAINER_NAME" curl --version >/dev/null 2>&1; then
        echo -e "${GREEN}✅ curl is available${NC}"
        
        # Test curl version
        version=$(docker exec "$CONTAINER_NAME" curl --version 2>/dev/null | head -1 || echo "not available")
        echo "   curl version: $version"
    else
        echo -e "${RED}❌ curl is not available${NC}"
    fi
else
    # For regular images, check openssl
    if docker exec "$CONTAINER_NAME" which openssl >/dev/null 2>&1; then
        echo -e "${GREEN}✅ OpenSSL is available${NC}"
        
        # Test OpenSSL version
        version=$(docker exec "$CONTAINER_NAME" openssl version 2>/dev/null || echo "not available")
        echo "   OpenSSL version: $version"
    else
        echo -e "${YELLOW}⚠️  OpenSSL is not available${NC}"
    fi
fi

echo ""
echo "📋 Checking container environment..."

if [ "$IS_SCRATCH" -eq 1 ]; then
    # For scratch images, we can't list directory contents, but we know what should be there
    echo "Scratch image contents (from Dockerfile):"
    echo "   - /bin/app (application binary)"
    echo "   - /usr/bin/curl"
    echo "   - /etc/ssl/certs/ca-certificates.crt"
    echo "   - curl libraries in /lib/"
else
    # For regular images, check what's in /etc/ssl/certs/
    echo "Contents of /etc/ssl/certs/:"
    docker exec "$CONTAINER_NAME" ls -la /etc/ssl/certs/ 2>/dev/null || echo "   Directory not accessible"
fi

echo ""
echo "🎯 Certificate test completed!"
echo "   If HTTPS connections work, CA certificates are properly configured"
echo "   If HTTPS connections fail, there might be issues with CA certificates" 