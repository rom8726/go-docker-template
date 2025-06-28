# Go Docker Template - Dockerfile
# Supports both regular Linux images and scratch images

# =============================================================================
# BUILD STAGE
# =============================================================================

FROM golang:1.24-alpine AS build

ENV GOPROXY="https://proxy.golang.org,direct"
ENV PROJECTDIR=/src
ENV CGO_ENABLED=0

RUN apk add --no-cache make curl

WORKDIR ${PROJECTDIR}
COPY go.mod go.sum ${PROJECTDIR}/
RUN go mod download

COPY . ${PROJECTDIR}/

RUN make build

# =============================================================================
# CURL EXTRACTION STAGE (for scratch images)
# =============================================================================

FROM alpine:3.19 AS curl-extract

RUN apk add --no-cache curl

# Extract curl and its dependencies
RUN mkdir -p /curl-deps && \
    cp /usr/bin/curl /curl-deps/ && \
    ldd /usr/bin/curl | grep "=>" | awk '{print $3}' | xargs -I {} cp {} /curl-deps/ && \
    cp /etc/ssl/certs/ca-certificates.crt /curl-deps/

# =============================================================================
# PRODUCTION IMAGE
# =============================================================================

# Option 1: Scratch image (minimal size, maximum security)
FROM scratch AS prod-scratch

# Copy curl and its dependencies
COPY --from=curl-extract /curl-deps/curl /usr/bin/curl
COPY --from=curl-extract /curl-deps/*.so* /lib/
COPY --from=curl-extract /curl-deps/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt

# Copy application binary and migrations
COPY --from=build /src/bin/app /bin/app
COPY --from=build /src/migrations /migrations

CMD ["/bin/app"]

# Option 2: Alpine image (more capabilities, but larger size)
FROM alpine:3.19 AS prod-alpine

# Install curl and CA certificates
RUN apk add --no-cache curl ca-certificates

# Create non-root user
RUN adduser -D -s /bin/sh appuser

# Copy application binary and migrations
COPY --from=build /src/bin/app /bin/app
COPY --from=build /src/migrations /migrations

# Change ownership of files
RUN chown -R appuser:appuser /bin/app /migrations

# Switch to non-root user
USER appuser

CMD ["/bin/app"]

# =============================================================================
# DEFAULT USES SCRATCH IMAGE
# =============================================================================

FROM prod-scratch AS prod
