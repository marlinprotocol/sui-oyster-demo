# Build stage
FROM node:24-alpine AS builder

# Install build dependencies
RUN apk add --no-cache python3 make g++

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production

# Runtime stage
FROM node:24-alpine

WORKDIR /app/demo

# Copy dependencies from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy source code
COPY src ./src
COPY package*.json ./

# Run the application
ENTRYPOINT ["node", "src/index.js"]
CMD ["/app/ecdsa.sec"]
