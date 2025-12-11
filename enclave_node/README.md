# Node.js Implementation

Node.js HTTP server that fetches SUI price from CoinGecko and signs it with secp256k1.

## Quick Start

```bash
# Build with Docker
docker build -t sui-oracle-node .
docker run -p 3000:3000 sui-oracle-node

# Or build reproducibly with Nix (pick your architecture)
cd ..
./nix.sh build-node-amd64   # or build-node-arm64
docker load < node-amd64-image.tar.gz
```

- Uses pure JS `@noble/secp256k1` (no native modules) for cross-arch reproducibility.
- `npmDepsHash` in build.nix guards against lock drift; update it only when `package-lock.json` changes.

### Updating dependencies (and npmDepsHash)

1) Edit `package.json` and run `npm install` (or `npm install <pkg>@<version>`) to refresh `package-lock.json`.
2) Let Nix tell you the new hash: run `./nix.sh build-node-amd64` (or arm64); Nix will fail with a message showing the “got” hash for `npmDepsHash`—copy that value into build.nix.
3) Re-run the build to confirm it succeeds and stays reproducible.

### Deploy with Oyster (example)

```bash
# After building and loading
docker tag sui-price-oracle:node-reproducible-latest <registry>/sui-price-oracle:node-reproducible-latest
docker push <registry>/sui-price-oracle:node-reproducible-latest

# Capture digest and update compose to use it (not a tag)
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' <registry>/sui-price-oracle:node-reproducible-latest)
sed -i '' "s@^\s*image: .*@    image: ${DIGEST}@" ./docker-compose.yml

oyster-cvm deploy \
	--wallet-private-key $PRIVATE_KEY \
	--docker-compose ./docker-compose.yml \
	--duration-in-minutes 60
```

**See the main [README.md](../README.md) for complete documentation including deployment, API reference, and integration.**
