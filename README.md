# uri — a formally verified URI (RFC 3986) library in F*

A verified RFC 3986 generic-URI grammar, built on the record `codec a`
combinator library (`fstar-codec`).  `uri` composes the scheme, authority
(host + optional port), path, query, and fragment into a single 0-admit codec,
plus a C-extractable Pulse leaf that dispatches the six URI scheme tags to a
single byte.

## Architecture

| Module | Layer | Extracts to |
|--------|-------|-------------|
| `Network.URI` | pure spec + codec (`Tot`/`Lemma`, `Seq`/`list`) | OCaml |
| `Network.URI.Pulse` | Pulse leaf (`fn`, `U8.t`, `A.array`) | C / OCaml / F# |

The pure `Network.URI` re-expresses the RFC 3986 grammar over the record
`codec a` combinators (Mandate 22: no bespoke scanners):

- `scheme` = `text_chars 64 is_scheme_char`
- `host` = `choice ipv6_host (choice ipv4_host domain_host)` (prefix-disjoint)
- `port` = `digits_to_int 5 (<= 65535)`
- `path` = slash-separated segments; `query` = `&`-separated `key=value` pairs

Each leaf (`ipv4_codec`/`ipv6_codec` from `fstar-ip`, `domain_codec` from
`fstar-dns`, `text_chars` from `fstar-text`) carries a proven `.roundtrip`;
the `uri` roundtrip is a chain of those fields.

## Dependencies

| Repo | Modules consumed |
|------|------------------|
| `fstar-codec` | `Data.Codec.Types`, `Data.Codec` |
| `fstar-text` | `Data.Text.Codec` (`text_chars`) |
| `fstar-basen` | `Data.BaseN.*` (IPv6 hex, transitive via `fstar-ip`) |
| `fstar-ip` | `Network.IPv4`, `Network.IPv6` |
| `fstar-dns` | `Network.DNS` (`domain_codec`) |

## Build

```
nix develop
make check            # 0-admit F* verification
```

Deliverables: `nix build .#checked .#ocaml .#native .#fsharp` + `nix flake
check`.

## License

AGPL-3.0-or-later, or a commercial license from the author (see `LICENSE.md`).
