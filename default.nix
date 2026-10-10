# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# uri — Network.URI verified URI (RFC 3986) library.
#
# Takes the F* toolchain as concrete derivations (no `pkgs` blob, no overlay
# assumption, no module-name/order arguments).  Module names and their
# dependency order live in the Makefile (the no-nix build); `checked` delegates
# to `make check`, exporting the toolchain paths the Makefile already reads.
#
# Dependencies (all injected as source dirs + pre-verified `.checked` caches):
#   - codec (Data.Codec.Types / Data.Codec)        — `fstar-codec`
#   - text  (Data.Text.Codec.*)                    — `fstar-text`
#   - basen (Data.BaseN.*)                         — `fstar-basen`
#   - ip    (Network.IP / IPv4 / IPv6)             — `fstar-ip`
#   - dns   (Network.DNS)                          — `fstar-dns`
#
# Artifacts (named by deliverable, not by backend):
#   - `checked` — F* verification of src/ + test/ (the 0-admit gate).
#   - `ocaml`   — findlib package shipping ALL OCaml-extractable modules:
#                 the pure spec (Network.URI) AND the Pulse leaf
#                 (Network.URI.Pulse, `--custard_backend OCaml`) as one dune lib.
#   - `native`  — C11 shared/static lib of the Pulse leaf (Network.URI.Pulse,
#                 `--custard_backend C`).
#   - `fsharp`  — .NET library of the Pulse leaf (`--custard_backend FSharp`).
#
# Returns { checked; ocaml; native; fsharp; }.

{
  fstar,
  fstar-checked,
  lib,
  ocamlPackages,
  stdenv,
  dotnet,
  codec-src,
  codec-checked,
  text-src,
  text-checked,
  basen-src,
  basen-checked,
  ip-src,
  ip-checked,
  dns-src,
  dns-checked,
}:

let
  inherit (stdenv) mkDerivation;

  pname = "uri";

  pure-modules = [
    "Network.URI"
  ];

  fstar-exe = "${fstar}/bin/fstar.exe";
  flib = "${fstar}/lib/fstar";
  ulib = "${flib}/ulib";

  pulse-incs = [
    "${flib}/pulse/common"
    "${flib}/pulse/common.checked"
    "${flib}/pulse/pulse/lib"
    "${flib}/pulse/pulse.checked"
  ];

  meta = {
    license = lib.licenses.agpl3Plus;
    longDescription = ''
      A formally verified URI (RFC 3986) library in F*.  The code license
      is AGPL-3.0-or-later; commercial licensing terms are available
      out-of-band from the author (see LICENSE.md).
    '';
    maintainers = [
      {
        name = "Tim Dysinger";
        email = "tim@dysinger.net";
      }
    ];
  };

  # The toolchain environment the Makefile reads (see its guards).
  make-env = ''
    export FSTAR="${fstar-exe}"
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

  # Common include flag set shared by every fstar.exe invocation (pure spec
  # and Pulse alike).  The five dependency source dirs are listed so F* can
  # resolve their module references.  Kept on a single line so splicing it
  # into a continued fstar.exe command line does not break the continuation.
  dep-includes = "--include ${codec-src}/src --include ${text-src}/src --include ${basen-src}/src --include ${ip-src}/src --include ${dns-src}/src --include ./src";

  seed-cache = ''
    cp ${fstar-checked}/*.checked cache/ 2>/dev/null || true
    cp ${codec-checked}/*.checked cache/ 2>/dev/null || true
    cp ${text-checked}/*.checked cache/ 2>/dev/null || true
    cp ${basen-checked}/*.checked cache/ 2>/dev/null || true
    cp ${ip-checked}/*.checked cache/ 2>/dev/null || true
    cp ${dns-checked}/*.checked cache/ 2>/dev/null || true
  '';

  checked = mkDerivation {
    pname = "${pname}-checked";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [
      fstar
      fstar-checked
    ];
    inherit meta;
    buildPhase = ''
      ${make-env}
      make check OUT="$out"
      if [ -d "$out/checked" ]; then
        find "$out/checked" -maxdepth 1 -name '*.checked' -exec sh -c 'mv "$1" "$out/"' _ {} \;
        rmdir "$out/checked" 2>/dev/null || true
      fi
      (cd "$out" && ls *.checked 2>/dev/null | sort) > "$out/manifest"
    '';
    installPhase = "true";
  };

  # ── OCaml source backend ────────────────────────────────────────────
  #
  # Extract the pure spec via legacy `--codegen OCaml`; the Pulse leaf via
  # `--codegen Custard --custard_backend OCaml`.  Every transitive pure spec
  # (codec + text + basen + ip + dns) is extracted LOCALLY so the bare
  # top-level module names the uri `.ml` emits resolve unwrapped (the
  # dependency findlib packages wrap them into `Codec.*`/`Text.*`/…).

  ocaml-lib-name = builtins.replaceStrings [ "-" ] [ "_" ] pname;
  # The uri pure module PLUS every transitive dependency pure module,
  # extracted locally (NOT consumed from the dep findlib packages, which wrap).
  ocaml-modules = (map (m: builtins.replaceStrings [ "." ] [ "_" ] m) pure-modules) ++ [
    "Data_Codec_Types"
    "Data_Codec"
    "Data_Text_Codec_Chars"
    "Data_Text_Codec"
    "Data_Text_Codec_Delims"
    "Data_Text_Codec_Zero"
    "Data_Text_Codec_UTF8"
    "Data_Text_Codec_UTF8String"
    "Data_BaseN_Base08"
    "Data_BaseN_Base16"
    "Data_BaseN_Base32"
    "Data_BaseN_Base64"
    "Data_BaseN"
    "Network_IP"
    "Network_IPv4"
    "Network_IPv6"
    "Network_DNS"
  ];

  ocaml-src = mkDerivation {
    name = "${pname}-ocaml-src";
    src = ./.;
    nativeBuildInputs = [
      fstar
      fstar-checked
    ];
    buildPhase = ''
            export ULIB="${ulib}"
            mkdir -p $out cache
            ${seed-cache}
            # 0) Extract each dependency's pure spec locally (unwrapped top-level names).
            for m in Data.Codec.Types Data.Codec; do
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src \
                --cache_checked_modules --cache_dir cache --odir cache ${codec-src}/src/$m.fst || exit 1
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include cache \
                --cache_checked_modules --cache_dir cache --codegen OCaml --odir $out ${codec-src}/src/$m.fst || exit 1
            done
            for m in Data.Text.Codec.Chars Data.Text.Codec Data.Text.Codec.Delims Data.Text.Codec.Zero Data.Text.Codec.UTF8 Data.Text.Codec.UTF8String; do
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include ${text-src}/src \
                --cache_checked_modules --cache_dir cache --odir cache ${text-src}/src/$m.fst || exit 1
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include ${text-src}/src --include cache \
                --cache_checked_modules --cache_dir cache --codegen OCaml --odir $out ${text-src}/src/$m.fst || exit 1
            done
            for m in Data.BaseN.Base08 Data.BaseN.Base16 Data.BaseN.Base32 Data.BaseN.Base64 Data.BaseN; do
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include ${basen-src}/src \
                --cache_checked_modules --cache_dir cache --odir cache ${basen-src}/src/$m.fst || exit 1
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include ${basen-src}/src --include cache \
                --cache_checked_modules --cache_dir cache --codegen OCaml --odir $out ${basen-src}/src/$m.fst || exit 1
            done
            for m in Network.IP Network.IPv4 Network.IPv6; do
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include ${basen-src}/src --include ${ip-src}/src \
                --cache_checked_modules --cache_dir cache --odir cache ${ip-src}/src/$m.fst || exit 1
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include ${basen-src}/src --include ${ip-src}/src --include cache \
                --cache_checked_modules --cache_dir cache --codegen OCaml --odir $out ${ip-src}/src/$m.fst || exit 1
            done
            for m in Network.DNS; do
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include ${text-src}/src --include ${dns-src}/src \
                --cache_checked_modules --cache_dir cache --odir cache ${dns-src}/src/$m.fst || exit 1
              ${fstar-exe} --no_default_includes --include "$ULIB" --include ${codec-src}/src --include ${text-src}/src --include ${dns-src}/src --include cache \
                --cache_checked_modules --cache_dir cache --codegen OCaml --odir $out ${dns-src}/src/$m.fst || exit 1
            done
            # 1) Extract the uri pure spec via legacy `--codegen OCaml`.
            for m in ${builtins.concatStringsSep " " pure-modules}; do
              ${fstar-exe} --no_default_includes --include "$ULIB" ${dep-includes} \
                --cache_checked_modules --cache_dir cache --odir cache src/$m.fst || exit 1
              ${fstar-exe} --no_default_includes --include "$ULIB" ${dep-includes} --include cache \
                --cache_checked_modules --cache_dir cache --codegen OCaml --odir $out src/$m.fst || exit 1
            done
            # 2) Extract the Pulse leaf (Network.URI.Pulse), OCaml backend.
            PULSE_INCS=""
            for d in ${lib.concatStringsSep " " pulse-incs}; do PULSE_INCS="$PULSE_INCS --include $d"; done
            ${fstar-exe} --no_default_includes --include "$ULIB" $PULSE_INCS ${dep-includes} \
              --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
              --z3rlimit 120 --cache_checked_modules --cache_dir cache --odir cache \
              src/Network.URI.Pulse.fst || exit 1
            ${fstar-exe} --no_default_includes --include "$ULIB" $PULSE_INCS ${dep-includes} --include cache \
              --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
              --cache_checked_modules --cache_dir cache \
              --codegen Custard --custard_backend OCaml --custard_monomorphize_types true \
              --custard_entry Network.URI.Pulse.encode_scheme \
              --custard_entry Network.URI.Pulse.decode_scheme \
              --odir $out src/Network.URI.Pulse.fst || exit 1
            # One dune library: pure spec + Pulse leaf together.
            cat > $out/dune-project <<DUNE_PROJECT
      (lang dune 3.11)
      (name ${pname}-ocaml)
      (package (name ${pname}-ocaml))
      DUNE_PROJECT
            cat > $out/dune <<DUNE
      (library
       (name ${ocaml-lib-name})
       (public_name ${pname}-ocaml)
       (modules ${builtins.concatStringsSep " " ocaml-modules} Custard)
       (libraries fstar.lib))
      DUNE
    '';
    installPhase = "true";
  };

  ocaml = ocamlPackages.buildDunePackage {
    pname = "${pname}-ocaml";
    version = "0.1.0";
    src = ocaml-src;
    inherit meta;
    propagatedBuildInputs = [ fstar ];
    buildInputs = with ocamlPackages; [
      batteries
      pprint
      stdint
      yojson
      zarith
      ppx_deriving
      ppx_deriving_yojson
    ];
    OCAMLPATH = "${fstar}/lib";
  };

  # ── native (C) backend ─────────────────────────────────────────────

  native = mkDerivation {
    pname = "${pname}-native";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [
      fstar
      fstar-checked
    ];
    inherit meta;
    buildPhase = ''
      mkdir -p $out cache
      ULIB="${ulib}"
      PULSE_INCS=""
      for d in ${lib.concatStringsSep " " pulse-incs}; do PULSE_INCS="$PULSE_INCS --include $d"; done
      ${seed-cache}
      for m in Network.URI Network.URI.Pulse; do
        ${fstar-exe} --no_default_includes --include "$ULIB" $PULSE_INCS ${dep-includes} \
          --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
          --z3rlimit 120 --cache_checked_modules --cache_dir cache --odir cache \
          src/$m.fst || exit 1
      done
      ${fstar-exe} --no_default_includes --include "$ULIB" $PULSE_INCS ${dep-includes} --include cache \
        --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
        --cache_checked_modules --cache_dir cache \
        --codegen Custard --custard_backend C --custard_monomorphize_types true \
        --custard_entry Network.URI.Pulse.encode_scheme \
        --custard_entry Network.URI.Pulse.decode_scheme \
        --odir $out src/Network.URI.Pulse.fst || exit 1
      cc -c -Wall -Wextra -Werror -std=c11 -O2 -fPIC -I $out $out/Custard.c -o $out/Custard.o
      if [ "$(uname -s)" = Darwin ]; then
        cc -dynamiclib $out/Custard.o -o $out/lib${pname}.dylib
      else
        cc -shared $out/Custard.o -o $out/lib${pname}.so
      fi
      ar rcs $out/lib${pname}.a $out/Custard.o
      cp $out/Custard.h $out/${pname}.h
    '';
    installPhase = "true";
  };

  # ── F# (.NET) backend ─────────────────────────────────────────────

  fsharp = mkDerivation {
    pname = "${pname}-fsharp";
    version = "0.1.0";
    src = ./.;
    nativeBuildInputs = [
      fstar
      fstar-checked
      dotnet
    ];
    inherit meta;
    buildPhase = ''
      mkdir -p $out cache src-out
      export DOTNET_CLI_TELEMETRY_OPTOUT=1
      export DOTNET_NOLOGO=1
      export DOTNET_SKIP_FIRST_TIME_EXPERIENCE=1
      export HOME=$NIX_BUILD_TOP
      ULIB="${ulib}"
      PULSE_INCS=""
      for d in ${lib.concatStringsSep " " pulse-incs}; do PULSE_INCS="$PULSE_INCS --include $d"; done
      ${seed-cache}
      for m in Network.URI Network.URI.Pulse; do
        ${fstar-exe} --no_default_includes --include "$ULIB" $PULSE_INCS ${dep-includes} \
          --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
          --z3rlimit 120 --cache_checked_modules --cache_dir cache --odir cache \
          src/$m.fst || exit 1
      done
      ${fstar-exe} --no_default_includes --include "$ULIB" $PULSE_INCS ${dep-includes} --include cache \
        --already_cached Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore \
        --cache_checked_modules --cache_dir cache \
        --codegen Custard --custard_backend FSharp --custard_monomorphize_types true \
        --custard_entry Network.URI.Pulse.encode_scheme \
        --custard_entry Network.URI.Pulse.decode_scheme \
        --odir src-out src/Network.URI.Pulse.fst || exit 1
      dotnet build src-out/Custard.fsproj -c Release -o $out || exit 1
    '';
    installPhase = "true";
  };

in
{
  inherit
    checked
    ocaml
    native
    fsharp
    ;
}
