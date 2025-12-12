{ pkgs, version, fenix, naersk, system, rust_target, arch ? "amd64" }:

let
  # Setup Rust toolchain with fenix
  toolchain = with fenix.packages.${system};
    combine [
      stable.cargo
      stable.rustc
      targets.${rust_target}.stable.rust-std
    ];
  
  # Setup naersk with the custom toolchain
  naersk' = naersk.lib.${system}.override {
    cargo = toolchain;
    rustc = toolchain;
  };
  
  # Use static compiler for musl builds
  cc = pkgs.pkgsStatic.stdenv.cc;
  
  # Filter source to only include necessary files for reproducibility
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      let 
        baseName = baseNameOf path;
        parentDir = baseNameOf (dirOf path);
      in 
        baseName == "Cargo.toml" ||
        baseName == "Cargo.lock" ||
        baseName == "src" ||
        parentDir == "src";  # Include files within src/
  };
  
  # Build the Rust binary as a static binary
  uncompressed = naersk'.buildPackage {
    pname = "sui-price-oracle";
    inherit version;
    inherit src;
    
    CARGO_BUILD_TARGET = rust_target;
    TARGET_CC = "${cc}/bin/${cc.targetPrefix}cc";
    nativeBuildInputs = [ cc ];
  };
  
  # Compress the binary with upx
  compressed = pkgs.runCommand "compressed" {
    nativeBuildInputs = [ pkgs.upx ];
  } ''
    mkdir -p $out/bin
    cp ${uncompressed}/bin/* $out/bin/
    chmod +w $out/bin/*
    upx $out/bin/*
  '';

in rec {
  inherit uncompressed compressed;
  
  docker = pkgs.dockerTools.buildImage {
    name = "sui-price-oracle";
    tag = "rust-reproducible-${arch}";
    copyToRoot = pkgs.buildEnv {
      name = "image-root";
      paths = [ compressed ];
      pathsToLink = [ "/bin" ];
    };
    config = {
      Entrypoint = [ "/bin/sui-price-oracle" "/app/ecdsa.sec" ];
    };
  };
  
  default = compressed;
}
