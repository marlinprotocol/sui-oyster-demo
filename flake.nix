{
  description = "SUI Price Oracle - Reproducible Docker images for Rust, Node.js, and Python enclaves";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/release-24.11";
    fenix = {
      url = "github:nix-community/fenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    naersk = {
      url = "github:nix-community/naersk";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, fenix, naersk }:
    let
      # Support both x86_64 and aarch64 build hosts
      supportedSystems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
      
      version = "0.1.0";
      
      # Target architectures for enclave deployments
      # Build Linux binaries regardless of host system
      mkTargets = system: 
        let
          # Always use Linux pkgs for the target architecture
          linuxPkgs = nixpkgs.legacyPackages.${system};
        in
        {
          amd64 = {
            platform = "linux/amd64";
            rust_target = "x86_64-unknown-linux-musl";
            # Use x86_64-linux pkgs or cross-compile from aarch64-linux
            pkgs = if system == "x86_64-linux"
                   then linuxPkgs
                   else linuxPkgs.pkgsCross.gnu64;
          };
          arm64 = {
            platform = "linux/arm64";
            rust_target = "aarch64-unknown-linux-musl";
            # Use aarch64-linux pkgs or cross-compile from x86_64-linux
            pkgs = if system == "aarch64-linux"
                   then linuxPkgs
                   else linuxPkgs.pkgsCross.aarch64-multiplatform;
          };
        };
      
      # Build for a specific target architecture
      buildForTarget = system: targets: targetName: target:
        let
          # Import language-specific builders
          rustBuild = import ./enclave_rust/build.nix { 
            inherit version fenix naersk system;
            pkgs = target.pkgs;
            rust_target = target.rust_target;
            arch = targetName;
          };
          pythonBuild = import ./enclave_python/build.nix { 
            inherit version;
            pkgs = target.pkgs;
            arch = targetName;
          };
          nodeBuild = import ./enclave_node/build.nix {
            inherit version;
            pkgs = target.pkgs;
            arch = targetName;
          };
        in
        {
          rust = rustBuild.docker;
          python = pythonBuild.docker;
          node = nodeBuild.docker;
        };
    in
    {
      packages = forAllSystems (system:
        let
          targets = mkTargets system;
        in
        {
          # AMD64 builds
          rust-amd64 = (buildForTarget system targets "amd64" targets.amd64).rust;
          python-amd64 = (buildForTarget system targets "amd64" targets.amd64).python;
          node-amd64 = (buildForTarget system targets "amd64" targets.amd64).node;
          
          # ARM64 builds
          rust-arm64 = (buildForTarget system targets "arm64" targets.arm64).rust;
          python-arm64 = (buildForTarget system targets "arm64" targets.arm64).python;
          node-arm64 = (buildForTarget system targets "arm64" targets.arm64).node;
          
          # Default to AMD64 Rust
          default = (buildForTarget system targets "amd64" targets.amd64).rust;
        }
      );
    };
}
