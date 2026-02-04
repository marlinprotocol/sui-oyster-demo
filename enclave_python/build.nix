{ pkgs, version, arch ? "amd64" }:

let
  # Filter source to only include necessary files for reproducibility
  src = pkgs.lib.cleanSourceWith {
    src = ./.;
    filter = path: type:
      let
        baseName = baseNameOf path;
        parentDir = baseNameOf (dirOf path);
      in
        baseName == "requirements.txt" ||
        baseName == "src" ||
        parentDir == "src";
  };

  # Python runtime with pinned dependencies from nixpkgs
  pythonEnv = pkgs.python3.withPackages (ps: [ ps.flask ps.requests ps.coincurve ]);

  # Install the application sources into /app
  app = pkgs.stdenv.mkDerivation {
    pname = "sui-price-oracle-python";
    inherit version src;

    installPhase = ''
      mkdir -p $out/app
      cp ${src}/src/main.py $out/app/main.py
      chmod +x $out/app/main.py
    '';
  };

in rec {
  inherit app pythonEnv;

  docker = pkgs.dockerTools.buildImage {
    name = "sui-price-oracle";
    tag = "python-reproducible-${arch}";
    copyToRoot = pkgs.buildEnv {
      name = "image-root";
      paths = [ pythonEnv app ];
      pathsToLink = [ "/bin" "/app" ];
    };
    config = {
      Entrypoint = [ "${pythonEnv}/bin/python3" "/app/main.py" "/app/ecdsa.sec" ];
    };
  };

  default = docker;
}
