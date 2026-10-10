# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

{
  description = "uri — verified URI (RFC 3986) library";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/c31cf09";
    flake-utils.url = "github:numtide/flake-utils";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    fstar = {
      # Fork of F* with the LSP server ported onto the v2026.09.20 base
      # (first stable tag shipping the Custard extractor).
      url = "github:dysinger/fstar/v2026.09.20+lsp";
      flake = false;
    };
    # The codec dependency (Data.Codec.Types / Data.Codec).
    fstar-codec.url = "github:dysinger/fstar-codec/5835aeb";
    # The text dependency (Data.Text.Codec — the `text_chars` string
    # combinator used for scheme/path/query runs).
    fstar-text.url = "github:dysinger/fstar-text";
    # The base-N dependency (Data.BaseN — IPv6 hex; pulled transitively by
    # fstar-ip, but pinned explicitly so Network.IPv6's `Data.BaseN.Base16`
    # resolves).
    fstar-basen.url = "github:dysinger/fstar-basen";
    # The IP dependency (Network.IPv4 / Network.IPv6).
    fstar-ip.url = "github:dysinger/fstar-ip";
    # The DNS dependency (Network.DNS — the `domain_codec` host form).
    fstar-dns.url = "github:dysinger/fstar-dns/4fde1e7";
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      flake-utils,
      treefmt-nix,
      fstar-codec,
      fstar-text,
      fstar-basen,
      fstar-ip,
      fstar-dns,
      ...
    }:
    flake-utils.lib.eachDefaultSystem (
      system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [
            (
              _final: prev:
              if prev.stdenv.isDarwin && prev.stdenv.isAarch64 then
                {
                  # Skip OCaml's own testsuite on aarch64-darwin.
                  ocaml-ng = prev.ocaml-ng // {
                    ocamlPackages_5_3 = prev.ocaml-ng.ocamlPackages_5_3.overrideScope (
                      _: _: {
                        ocaml = prev.ocaml-ng.ocamlPackages_5_3.ocaml.overrideAttrs (_: {
                          checkPhase = "true";
                        });
                      }
                    );
                  };
                }
              else
                { }
            )
            (
              _final: prev:
              let
                ocamlPackages = prev.ocaml-ng.ocamlPackages_5_3;
                z3 = prev.callPackage (inputs.fstar + "/.nix/z3.nix") { };
                version = "2026.09.20+lsp";

                fstar =
                  (ocamlPackages.callPackage (inputs.fstar + "/.nix/fstar.nix") {
                    inherit version z3;
                    karamel-src = prev.emptyDirectory;
                    karamelOcamlDeps = [ ];
                    ocamlLibraryPath = "";
                  }).overrideAttrs
                    (old: {
                      nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.git ];
                      buildPhase = ''
                        export PATH="${z3}/bin:$PATH"
                        export FSTAR_USE_KRML_EXE=1 KRML_EXE=/bin/true
                        mkdir -p karamel
                        printf 'all:\n\t@true\ninstall:\n\t@true\n' > karamel/Makefile
                        make OTHERFLAGS='--z3rlimit 20 --retry 3'
                      '';
                      installPhase = ''
                        export FSTAR_USE_KRML_EXE=1 KRML_EXE=/bin/true
                        mkdir -p karamel
                        printf 'all:\n\t@true\ninstall:\n\t@true\n' > karamel/Makefile
                        PREFIX=$out make install

                        for binary in $out/bin/*
                        do
                          wrapProgram $binary --prefix PATH ":" ${z3}/bin
                        done

                        cd $out
                        installShellCompletion --bash ${inputs.fstar + "/.completion/bash/fstar.exe.bash"}
                        installShellCompletion --fish ${inputs.fstar + "/.completion/fish/fstar.exe.fish"}
                        installShellCompletion --zsh --name _fstar.exe ${inputs.fstar + "/.completion/zsh/__fstar.exe"}
                      '';
                    });

                fstar-checked = prev.runCommand "fstar-checked" { nativeBuildInputs = [ fstar ]; } ''
                  mkdir -p $out
                  cp ${fstar}/lib/fstar/ulib.checked/*.checked $out/ 2>/dev/null || true
                  echo "checked: $(ls $out/*.checked 2>/dev/null | wc -l) files"
                '';
              in
              {
                inherit fstar fstar-checked;
                inherit ocamlPackages;
              }
            )
          ];
        };

        inherit (pkgs)
          stdenv
          fstar
          fstar-checked
          lib
          dotnet-sdk_10
          ;
        inherit (pkgs) ocamlPackages;

        codec-src = fstar-codec;
        codec-checked = fstar-codec.packages.${system}.checked;
        text-src = fstar-text;
        text-checked = fstar-text.packages.${system}.checked;
        basen-src = fstar-basen;
        basen-checked = fstar-basen.packages.${system}.checked;
        ip-src = fstar-ip;
        ip-checked = fstar-ip.packages.${system}.checked;
        dns-src = fstar-dns;
        dns-checked = fstar-dns.packages.${system}.checked;

        _pkg = import ./default.nix {
          inherit
            fstar
            fstar-checked
            lib
            ocamlPackages
            stdenv
            codec-src
            codec-checked
            text-src
            text-checked
            basen-src
            basen-checked
            ip-src
            ip-checked
            dns-src
            dns-checked
            ;
          dotnet = dotnet-sdk_10;
        };

        treefmtModule = treefmt-nix.lib.evalModule pkgs ./treefmt.nix;

      in
      {
        formatter = treefmtModule.config.build.wrapper;

        checks.formatting = treefmtModule.config.build.check self;

        packages.default = _pkg.native;
        packages.checked = _pkg.checked;
        packages.ocaml = _pkg.ocaml;
        packages.native = _pkg.native;
        packages.fsharp = _pkg.fsharp;

        devShells.default = pkgs.mkShell {
          dontDetectOcamlConflicts = true;
          shellHook = ''
            export FSTAR_CHECKED="${fstar-checked}"
            export CODEC_SRC="${codec-src}"
            export CODEC_CHECKED="${codec-checked}"
            export TEXT_SRC="${text-src}"
            export TEXT_CHECKED="${text-checked}"
            export BASEN_SRC="${basen-src}"
            export BASEN_CHECKED="${basen-checked}"
            export IP_SRC="${ip-src}"
            export IP_CHECKED="${ip-checked}"
            export DNS_SRC="${dns-src}"
            export DNS_CHECKED="${dns-checked}"
          '';
          buildInputs = with pkgs; [
            fstar
            dotnet-sdk_10
            git
            ocaml
            ocamlPackages.ocaml-lsp
          ];
        };
      }
    );
}
