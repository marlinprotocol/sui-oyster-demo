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
}

run_nix() {
    eval "${NIX_CMD} $@"
}

show_help() {
    cat << EOF
Nix Build Helper (Docker-based - no Nix installation required!)

Usage: ./nix.sh <command>

Commands:
  build-rust     Build Rust Docker image
  build-node     Build Node.js Docker image
  build-python   Build Python Docker image
  build-all      Build all implementations
  
  update         Update dependencies
  clean          Clean build artifacts
  help           Show this help

Examples:
  ./nix.sh build-rust
  ./nix.sh update

Note: This script uses Docker to run Nix - you only need Docker installed!
EOF
}

case "${1:-}" in
    build-rust)
        check_docker
        print_header "Building Rust Docker image (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build .#rust && cat result > /workspace/rust-image.tar.gz"
        print_success "Build complete: rust-image.tar.gz"
        print_info "Load with: docker load < rust-image.tar.gz"
        ;;
    
    build-node)
        check_docker
        print_header "Building Node.js Docker image (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build .#node && cat result > /workspace/node-image.tar.gz"
        print_success "Build complete: node-image.tar.gz"
        print_info "Load with: docker load < node-image.tar.gz"
        ;;
    
    build-python)
        check_docker
        print_header "Building Python Docker image (using Nix in Docker)"
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build .#python && cat result > /workspace/python-image.tar.gz"
        print_success "Build complete: python-image.tar.gz"
        print_info "Load with: docker load < python-image.tar.gz"
        ;;
    
    build-all)
        check_docker
        print_header "Building all implementations (using Nix in Docker)"
        print_info "Building Rust..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build .#rust && cat result > /workspace/rust-image.tar.gz"
        print_info "Building Node.js..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build .#node && cat result > /workspace/node-image.tar.gz"
        print_info "Building Python..."
        docker run --rm -v "$(pwd):/workspace" -w /workspace \
            -e NIX_CONFIG='experimental-features = nix-command flakes' \
            ${NIX_IMAGE} \
            sh -c "git config --global --add safe.directory /workspace && nix build .#python && cat result > /workspace/python-image.tar.gz"
        print_success "All builds complete"
        echo "  Rust:   rust-image.tar.gz"
        echo "  Node:   node-image.tar.gz"
        echo "  Python: python-image.tar.gz"
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
