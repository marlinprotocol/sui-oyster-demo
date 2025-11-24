# Build stage
FROM rust:1.91-alpine AS builder

# Install build dependencies
RUN apk add --no-cache musl-dev openssl-dev openssl-libs-static

# Create app directory
WORKDIR /app

# Copy manifests
COPY Cargo.toml ./

# Copy source code
COPY src ./src

# Build the application
RUN cargo build --release

# Runtime stage
FROM alpine:latest

# Install runtime dependencies
RUN apk add --no-cache ca-certificates libgcc

WORKDIR /app/demo

# Copy the binary from builder
COPY --from=builder /app/target/release/sui-price-oracle /app/demo/sui-price-oracle

# Run the binary
ENTRYPOINT ["/app/demo/sui-price-oracle"]
CMD ["/app/ecdsa.sec"]