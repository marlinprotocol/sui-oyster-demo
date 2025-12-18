# Node.js Implementation

Node.js HTTP server that fetches SUI price from CoinGecko and signs it with secp256k1.

## Quick Start

```bash
# Build with Docker
docker build -t sui-oracle-node .
docker run -p 3000:3000 sui-oracle-node

# Or build reproducibly with Nix (pick your architecture)
cd ..
./nix.sh build-node-arm64   # or build-node-amd64
docker load < ./node-arm64-image.tar.gz
```

- Uses pure JS `@noble/secp256k1` (no native modules) for cross-arch reproducibility.
- `npmDepsHash` in build.nix guards against lock drift; update it only when `package-lock.json` changes.

### Updating dependencies (and npmDepsHash)

1) Edit `package.json` and run `npm install` (or `npm install <pkg>@<version>`) to refresh `package-lock.json`.
2) Let Nix tell you the new hash: run `./nix.sh build-node-arm64` (or amd64); Nix will fail with a message showing the “got” hash for `npmDepsHash`—copy that value into build.nix.
3) Re-run the build to confirm it succeeds and stays reproducible.

### Deploy with Oyster (example)

```bash
# Replace <registry> with your docker hub username
docker tag sui-price-oracle:node-reproducible-arm64 <registry>/sui-price-oracle:node-reproducible-arm64
docker push <registry>/sui-price-oracle:node-reproducible-arm64

# Capture digest and update compose to use it (not a tag)
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' <registry>/sui-price-oracle:node-reproducible-arm64)
sed -i '' "s@^\s*image: .*@    image: ${DIGEST}@" ./docker-compose.yml

oyster-cvm deploy \
	--wallet-private-key $PRIVATE_KEY \
	--docker-compose ./docker-compose.yml \
    --instance-type c6g.xlarge \
	--duration-in-minutes 60 \
	--deployment sui
```

**See the main [README.md](../README.md) for complete documentation including deployment, API reference, and integration.**
