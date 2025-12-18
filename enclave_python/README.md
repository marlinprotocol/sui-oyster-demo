# Python Implementation

Python HTTP server that fetches SUI price from CoinGecko and signs it with secp256k1.

## Quick Start

```bash
# Build with Docker
docker build -t sui-oracle-python .
docker run -p 3000:3000 sui-oracle-python

# Or build reproducibly with Nix (pick your architecture)
cd ..
./nix.sh build-python-arm64   # or build-python-amd64
docker load < ./python-arm64-image.tar.gz
```

### Deploy with Oyster (example)

```bash
# Replace <registry> with your docker hub username
docker tag sui-price-oracle:python-reproducible-arm64 <registry>/sui-price-oracle:python-reproducible-arm64
docker push <registry>/sui-price-oracle:python-reproducible-arm64

# Capture digest and update compose to use it (not a tag)
DIGEST=$(docker inspect --format='{{index .RepoDigests 0}}' <registry>/sui-price-oracle:python-reproducible-arm64)
sed -i '' "s@^\s*image: .*@    image: ${DIGEST}@" ./docker-compose.yml

oyster-cvm deploy \
	--wallet-private-key $PRIVATE_KEY \
	--docker-compose ./docker-compose.yml \
    --instance-type c6g.xlarge \
	--duration-in-minutes 60 \
	--deployment sui
```

**See the main [README.md](../README.md) for complete documentation including deployment, API reference, and integration.**
