#!/usr/bin/env bash
# Nix build helper script - uses Docker to run Nix (no local install needed!)

set -e

COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_BLUE='\033[0;34m'
COLOR_RED='\033[0;31m'
COLOR_RESET='\033[0m'

NIX_IMAGE="nixos/nix:latest"
NIX_CMD="docker run --rm -it -v \$(pwd):/workspace -w /workspace -e NIX_CONFIG='experimental-features = nix-command flakes' ${NIX_IMAGE}"

print_header() {
    echo -e "${COLOR_BLUE}==> $1${COLOR_RESET}"
}

print_success() {
    echo -e "${COLOR_GREEN}✓ $1${COLOR_RESET}"
}

print_info() {
    echo -e "${COLOR_YELLOW}→ $1${COLOR_RESET}"
}

print_error() {
    echo -e "${COLOR_RED}✗ $1${COLOR_RESET}"
}

check_docker() {
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed"
        echo "Install Docker from: https://docs.docker.com/get-docker/"
        exit 1
    fi
    
    if ! docker info &> /dev/null; then
        print_error "Docker daemon is not running"
        echo "Please start Docker and try again"
        exit 1
    fi

    # Recommend Docker 29+ so hashes remain stable when running `docker load` (containerd storage)
    server_version=$(docker version --format '{{.Server.Version}}' 2>/dev/null || true)
    if [[ -n "$server_version" ]]; then
        server_major=${server_version%%.*}
        if [[ "$server_major" -lt 29 ]]; then
            print_info "Docker >=29 recommended for stable image hashes on docker load (detected ${server_version}). Builds still run, but digests may differ after load."
        fi
    else
        print_info "Unable to detect Docker version; Docker 29+ recommended for stable image hashes on docker load."
    fi
}

run_nix() {
    eval "${NIX_CMD} $@"
}

show_help() {
    cat << EOF
Nix Build Helper (Docker-based - no Nix installation required!)

Usage: ./nix.sh <command>

Commands:
  build-rust-amd64       Build Rust Docker image for Linux AMD64
  build-rust-arm64       Build Rust Docker image for Linux ARM64
  build-python-amd64     Build Python Docker image for Linux AMD64
  build-python-arm64     Build Python Docker image for Linux ARM64
    build-node-amd64       Build Node.js Docker image for Linux AMD64
    build-node-arm64       Build Node.js Docker image for Linux ARM64
  build-all              Build all implementations for both architectures
  
  update                 Update dependencies
  clean                  Clean build artifacts
  help                   Show this help

Examples:
  ./nix.sh build-rust-amd64
  ./nix.sh build-python-arm64
  ./nix.sh build-all

Note: This script uses Docker to run Nix - you only need Docker installed!
EOF
}

case "${1:-}" in
    build-rust-amd64)
        check_docker
        print_header "Building Rust Docker image for Linux AMD64 (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system x86_64-linux .#rust-amd64 && cat result > /workspace/rust-amd64-image.tar.gz"
        print_success "Build complete: rust-amd64-image.tar.gz"
        print_info "Load with: docker load < ./rust-amd64-image.tar.gz"
        ;;
    
    build-rust-arm64)
        check_docker
        print_header "Building Rust Docker image for Linux ARM64 (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system aarch64-linux .#rust-arm64 && cat result > /workspace/rust-arm64-image.tar.gz"
        print_success "Build complete: rust-arm64-image.tar.gz"
        print_info "Load with: docker load < ./rust-arm64-image.tar.gz"
        ;;
    
    build-python-amd64)
        check_docker
        print_header "Building Python Docker image for Linux AMD64 (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system x86_64-linux .#python-amd64 && cat result > /workspace/python-amd64-image.tar.gz"
        print_success "Build complete: python-amd64-image.tar.gz"
        print_info "Load with: docker load < ./python-amd64-image.tar.gz"
        ;;
    
    build-python-arm64)
        check_docker
        print_header "Building Python Docker image for Linux ARM64 (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system aarch64-linux .#python-arm64 && cat result > /workspace/python-arm64-image.tar.gz"
        print_success "Build complete: python-arm64-image.tar.gz"
        print_info "Load with: docker load < ./python-arm64-image.tar.gz"
        ;;
    
    build-node-amd64)
        check_docker
        print_header "Building Node.js Docker image for Linux AMD64 (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system x86_64-linux .#node-amd64 && cat result > /workspace/node-amd64-image.tar.gz"
        print_success "Build complete: node-amd64-image.tar.gz"
        print_info "Load with: docker load < ./node-amd64-image.tar.gz"
        ;;
    build-node-arm64)
        check_docker
        print_header "Building Node.js Docker image for Linux ARM64 (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system aarch64-linux .#node-arm64 && cat result > /workspace/node-arm64-image.tar.gz"
        print_success "Build complete: node-arm64-image.tar.gz"
        print_info "Load with: docker load < ./node-arm64-image.tar.gz"
        ;;
    
    build-all)
        check_docker
        print_header "Building all implementations (using Nix in Docker)"
        print_info "Building Rust AMD64..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system x86_64-linux .#rust-amd64 && cat result > /workspace/rust-amd64-image.tar.gz"
        print_info "Building Rust ARM64..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system aarch64-linux .#rust-arm64 && cat result > /workspace/rust-arm64-image.tar.gz"
        print_info "Building Python AMD64..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system x86_64-linux .#python-amd64 && cat result > /workspace/python-amd64-image.tar.gz"
        print_info "Building Python ARM64..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system aarch64-linux .#python-arm64 && cat result > /workspace/python-arm64-image.tar.gz"
        print_info "Building Node.js AMD64..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system x86_64-linux .#node-amd64 && cat result > /workspace/node-amd64-image.tar.gz"
        print_info "Building Node.js ARM64..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build --system aarch64-linux .#node-arm64 && cat result > /workspace/node-arm64-image.tar.gz"
        print_success "All builds complete"
        echo "  Rust AMD64:   rust-amd64-image.tar.gz"
        echo "  Rust ARM64:   rust-arm64-image.tar.gz"
        echo "  Python AMD64: python-amd64-image.tar.gz"
        echo "  Python ARM64: python-arm64-image.tar.gz"
        echo "  Node AMD64:   node-amd64-image.tar.gz"
        echo "  Node ARM64:   node-arm64-image.tar.gz"
        ;;
    
    update)
        check_docker
        print_header "Updating dependencies (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix flake update"
        print_success "Dependencies updated"
        print_info "Don't forget to commit flake.lock"
        ;;
    
    clean)
        print_header "Cleaning build artifacts"
        rm -f *-image.tar.gz result result-*
        print_success "Cleaned build artifacts"
        ;;
    
    help|--help|-h|"")
        show_help
        ;;
    
    *)
        print_error "Unknown command: $1"
        echo ""
        show_help
        exit 1
        ;;
esac
