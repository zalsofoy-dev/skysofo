FROM golang:1.20-alpine AS builder

WORKDIR /src

# Install build dependencies
RUN apk add --no-cache ca-certificates tzdata

# Copy source files
COPY config.json.tpl /src/config.json.tpl
COPY main.go /src/main.go
COPY go.mod /src/go.mod

# Build optimized static binary
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build \
    -ldflags='-s -w -extldflags "-static"' \
    -tags netgo \
    -o /configgen \
    .

FROM ghcr.io/xtls/xray-core:latest

# Copy only necessary files
COPY --from=builder /configgen /configgen
COPY config.json.tpl /config.json.tpl

# Metadata
LABEL maintainer="skysofo"
LABEL description="Optimized VLESS+WS+TLS Xray configuration"

# Expose optimized ports
EXPOSE 443/tcp 8080/tcp

# Health check (optional, useful for orchestration)
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD curl -f http://127.0.0.1:10085/ || exit 1

# Run the config generator which spawns xray
ENTRYPOINT ["/configgen"]
