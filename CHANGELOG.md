# Changelog

All notable changes to this project are documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Migrated `Network.URI` off the deleted GADT codec API (`make_codec`/
  `encode_spec`/`decode_spec`/`Data.Codec.Lemmas`) onto the record `codec a`
  combinator API (Mandate 22: no bespoke scanners — every parse/serialize step
  is a combinator).  The scheme/segment/query runs use `text_chars` (the
  verified bounded-greedy string combinator); the port uses `digits_to_int`;
  the host is a `choice` of `fstar-ip`'s `ipv4_codec`/`ipv6_codec` and
  `fstar-dns`'s `domain_codec`.  0-admit.
- Re-expressed the `domain_host` mapping against the new `fstar-dns`
  `Network.DNS.domain_codec` (`domain_name` now carries `fully_qualified`).
- Replaced every `admit ()`/`magic ()` (`uri_of_string_tot`,
  `authority_of_string`, `host_of_string`, `lemma_scheme_valid`) with pure
  `Tot` functions over the codec's `dec`, and deleted both
  `--admit_smt_queries true` regions.
- Ported `Network.URI.Low` → `Network.URI.Pulse` (the KaRaMeL `.Low`
  convention is retired; the Pulse/Custard layer is the successor): a
  `uri_scheme` tag-dispatch leaf (`encode_scheme`/`decode_scheme` `fn`s with
  pointwise `ensures`), 0-admit, extracting to C11 (`-Wall -Wextra -Werror`)
  / OCaml / F#.

### Fixed

- `uri_of_string`/`authority_of_string`/`host_of_string` now REJECT a
  non-ASCII input (via a local `string_to_ascii_bytes`, mirroring
  `fstar-dns`) rather than silently truncating it.

## [0.1.0] — initial extraction

### Added

- Extracted `Network.URI` out of the original monorepo into a standalone
  repository built from `fstar-nix-flake-template`.
- Source modules:
  - `Network.URI` — the `uri_host`/`authority`/`uri` types, the RFC 3986
    character predicates, and the composed `uri_codec` (scheme, authority,
    path, query, fragment) built from the record `codec a` combinators.
  - `Network.URI.Pulse` — C-extractable scheme tag-dispatch leaf (six
    `uri_scheme` tags map to one byte).
- Test module: `Network.URI.Test.Integration` (100% coverage anchors + an
  RFC 3986 concrete vector).
- Nix flake targets: `.#checked`, `.#ocaml`, `.#native`, `.#fsharp`.
- Flake inputs: `fstar-codec`, `fstar-text`, `fstar-basen`, `fstar-ip`,
  `fstar-dns` (the five dependency libraries).
- Dual licensing: AGPL-3.0-or-later, or a commercial license from the author.

### Changed

- Migrated the codec off the deleted GADT API (`make_codec`/`encode_spec`/
  `decode_spec`/`Data.Codec.Lemmas`) onto the record `codec a` combinator API.
- Renamed the C leaf `Network.URI.Low` → `Network.URI.Pulse`.
- Rolled F\* forward to `v2026.09.20+lsp` (first stable tag shipping the
  Custard extractor).
- Removed the KaRaMeL/Low\* toolchain and all its targets.

### Notes

- Zero admits / zero magic / zero `assume` in `src/`.  The integration test
  disables SMT (`--admit_smt_queries true`) for bare coverage anchors only —
  each anchor is a `let _ = f` value reference that emits no verification
  conditions, so no claim is admitted.
