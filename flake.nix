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
      # Support Linux (x86_64 and ARM64) for enclave deployments
      systems = [ "x86_64-linux" "aarch64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs systems;
      
      version = "0.1.0";
      
      # System-specific configuration for static builds
      systemConfig = system: {
        inherit system;
        rust_target = if system == "x86_64-linux" then "x86_64-unknown-linux-musl" else "aarch64-unknown-linux-musl";
        static = true;
      };
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          config = systemConfig system;
          
          # Import language-specific builders with naersk/fenix for Rust
          rustBuild = import ./enclave_rust/build.nix { 
            inherit pkgs version fenix naersk;
            systemConfig = config;
          };
          nodeBuild = import ./enclave_node/build.nix { 
            inherit pkgs version;
          };
          pythonBuild = import ./enclave_python/build.nix { 
            inherit pkgs version;
          };
        in
        {
          # Individual implementations
          rust = rustBuild.docker;
          node = nodeBuild.docker;
          python = pythonBuild.docker;
          
          # Default to Rust (recommended for production)
          default = rustBuild.docker;
        }
      );
    };
}
