{
  description = "QuickNotes — reproducible Nix flake (Lab 11)";

  inputs = {
    # Pin a channel that ships Go ≥ 1.24 (app/go.mod).
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
  };

  outputs =
    { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs {
        inherit system;
        # Pure evaluation; no impurity.
        config = { };
      };

      # Prefer an explicit Go 1.24 toolchain if the channel's default lags.
      buildGo = pkgs.buildGoModule.override {
        go = pkgs.go_1_24 or pkgs.go;
      };

      quicknotes = buildGo {
        pname = "quicknotes";
        version = "0.1.0";
        src = ./app;

        # Zero third-party modules (only stdlib). nixpkgs requires null here —
        # a pinned empty-tree hash is rejected ("vendor folder is empty").
        vendorHash = null;

        env.CGO_ENABLED = "0";
        ldflags = [
          "-s"
          "-w"
        ];

        meta = with pkgs.lib; {
          description = "QuickNotes API (DevOps-Intro)";
          mainProgram = "quicknotes";
          license = licenses.mit;
        };
      };

      # Deterministic OCI image WITHOUT Docker daemon (dockerTools).
      dockerImage = pkgs.dockerTools.buildImage {
        name = "quicknotes";
        tag = "nix";
        # Fixed creation time → bit-identical tarball across rebuilds.
        created = "1970-01-01T00:00:01Z";
        copyToRoot = pkgs.buildEnv {
          name = "quicknotes-root";
          paths = [
            quicknotes
            pkgs.dockerTools.fakeNss
            pkgs.dockerTools.usrBinEnv
            pkgs.cacert
          ];
          pathsToLink = [
            "/bin"
            "/etc"
          ];
        };
        config = {
          Entrypoint = [ "/bin/quicknotes" ];
          ExposedPorts = {
            "8080/tcp" = { };
          };
          # Lab 6 discipline: non-root (nobody from fakeNss = uid 65534).
          User = "65534:65534";
          Env = [
            "ADDR=:8080"
            "DATA_PATH=/tmp/notes.json"
            "SEED_PATH=/tmp/empty-seed.json"
            "SSL_CERT_FILE=/etc/ssl/certs/ca-bundle.crt"
          ];
          WorkingDir = "/tmp";
        };
        # Writable tmp for DATA_PATH under nonroot.
        extraCommands = "mkdir -p tmp; chmod 1777 tmp; printf '[]' > tmp/empty-seed.json; chmod 644 tmp/empty-seed.json";
      };
    in
    {
      packages.${system} = {
        quicknotes = quicknotes;
        default = quicknotes;
        docker = dockerImage;
      };

      devShells.${system}.default = pkgs.mkShell {
        packages = [
          pkgs.go_1_24 or pkgs.go
          pkgs.gopls
          pkgs.golangci-lint
        ];
      };
    };
}
