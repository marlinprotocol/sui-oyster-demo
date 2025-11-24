# Build stage
FROM python:3.14-alpine AS builder

# Install build dependencies
RUN apk add --no-cache gcc musl-dev libffi-dev

# Create app directory
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir --prefix=/install -r requirements.txt

# Runtime stage
FROM python:3.14-alpine

# Install runtime dependencies
RUN apk add --no-cache libgcc libffi

WORKDIR /app/demo

# Copy dependencies from builder
COPY --from=builder /install /usr/local

# Copy source code
COPY src/main.py ./main.py

# Make script executable
RUN chmod +x main.py

# Run the application
ENTRYPOINT ["python3", "main.py"]
CMD ["/app/ecdsa.sec"]
