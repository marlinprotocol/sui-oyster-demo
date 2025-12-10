# Rust Implementation

Rust HTTP server that fetches SUI price from CoinGecko and signs it with secp256k1.

## Quick Start

```bash
# Build with Docker
docker build -t sui-oracle-rust .
docker run -v $(pwd)/keys/ecdsa.sec:/app/ecdsa.sec:ro -p 3000:3000 sui-oracle-rust

# Or build with Nix for reproducibility
cd ..
./nix.sh build-rust
docker load < result
```

**See the main [README.md](../README.md) for complete documentation including deployment, API reference, and integration.**
