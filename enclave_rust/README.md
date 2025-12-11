# Rust Implementation

Rust HTTP server that fetches SUI price from CoinGecko and signs it with secp256k1.

## Quick Start

```bash
# Build with Docker
docker build -t sui-oracle-rust .
docker run -v $(pwd)/keys/ecdsa.sec:/app/ecdsa.sec:ro -p 3000:3000 sui-oracle-rust

# Or build reproducibly with Nix (pick your architecture)
cd ..
./nix.sh build-rust-amd64   # or build-rust-arm64
docker load < rust-amd64-image.tar.gz
```

### Deploy with Oyster (example)

```bash
docker tag sui-price-oracle:rust-reproducible-latest <registry>/sui-price-oracle:rust-reproducible-latest
docker push <registry>/sui-price-oracle:rust-reproducible-latest

# Capture digest and update compose to use it (not a tag)
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' <registry>/sui-price-oracle:rust-reproducible-latest)
sed -i '' "s@^\s*image: .*@    image: ${DIGEST}@" ./docker-compose.yml

oyster-cvm deploy \
	--wallet-private-key $PRIVATE_KEY \
	--docker-compose ./docker-compose.yml \
	--duration-in-minutes 60
```

**See the main [README.md](../README.md) for complete documentation including deployment, API reference, and integration.**
