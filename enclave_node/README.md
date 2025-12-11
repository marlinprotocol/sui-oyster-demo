# Node.js Implementation

Node.js HTTP server that fetches SUI price from CoinGecko and signs it with secp256k1.

## Quick Start

```bash
# Build with Docker
docker build -t sui-oracle-node .
docker run -p 3000:3000 sui-oracle-node

# Or build with Nix for reproducibility
cd ..
./nix.sh build-node
docker load < result
```

**See the main [README.md](../README.md) for complete documentation including deployment, API reference, and integration.**
