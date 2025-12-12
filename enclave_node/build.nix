{ pkgs, version, arch ? "amd64" }:

let
  # Use Node 20 for stability
  nodejs = pkgs.nodejs_20;

  # Filter source to only what is needed for reproducible builds
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      let
        baseName = baseNameOf path;
        parentDir = baseNameOf (dirOf path);
      in
        baseName == "package.json" ||
        baseName == "package-lock.json" ||
        baseName == "src" ||
        parentDir == "src";
  };

  # Build the Node.js application with locked dependencies (pure JS only)
  app = pkgs.buildNpmPackage {
    pname = "sui-price-oracle-node";
    inherit version src nodejs;

    # Hash for dependencies - pure JS only, no native modules
    npmDepsHash = "sha256-HOZO9+yHJoSu3k653D8PKR/MJnML0jnpuMDnkrzdv9I=";

    dontNpmBuild = true;
    npmInstallFlags = [ "--omit=dev" ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/app
      cp -r . $out/app
      runHook postInstall
    '';
  };

in rec {
  inherit app nodejs;

  docker = pkgs.dockerTools.buildImage {
    name = "sui-price-oracle";
    tag = "node-reproducible-${arch}";
    copyToRoot = pkgs.buildEnv {
      name = "image-root";
      paths = [ nodejs app pkgs.cacert ];
      pathsToLink = [ "/bin" "/app" ];
    };
    config = {
      WorkingDir = "/app";
      Entrypoint = [ "${nodejs}/bin/node" "/app/src/index.js" "/app/ecdsa.sec" ];
      Env = [ "SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt" ];
    };
  };

  default = docker;
}
