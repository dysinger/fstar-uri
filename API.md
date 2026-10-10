# Network.URI API Reference

## Types

### Network.URI — Pure Spec
| Name | Kind | Description |
|------|------|-------------|
| `uri_host` | sum | `IPv4Host of ipv4` \| `IPv6Host of ipv6` \| `DomainHost of domain_name` |
| `authority` | record | `userinfo : option string`, `host : uri_host`, `port : option int` |
| `path` | alias | `list string` (path segments) |
| `query_param` | record | `key : string`, `value : string` |
| `query` | alias | `list query_param` |
| `uri` | record | `scheme : string`, `authority : option authority`, `path : path`, `query : option query`, `fragment : option string` |

### Network.URI.Pulse — Extractable Leaf
| Name | Kind | Description |
|------|------|-------------|
| `uri_scheme` | enum | `US_HTTP` / `US_HTTPS` / `US_FTP` / `US_WS` / `US_WSS` / `US_Other` |
| `opt_uri_scheme` | sum | `OUR_None` / `OUR_Some of (uri_scheme & U32.t)` |

## Character predicates (RFC 3986)

| Function | Signature | Description |
|----------|-----------|-------------|
| `is_scheme_char` | `char -> bool` | `ALPHA ( ALPHA \| DIGIT \| + \| - \| . )*` |
| `is_unreserved` | `char -> bool` | `ALPHA \| DIGIT \| - \| . \| _ \| ~` |
| `is_sub_delim` | `char -> bool` | `! $ & ' ( ) * + , ; =` |
| `is_pchar` | `char -> bool` | `unreserved \| sub-delims \| : \| @` (any char except `/ ? #`) |
| `is_query_char` | `char -> bool` | any char except `= & #` |
| `code_of` | `char -> int` | the integer code point of a character |

## Codec

| Function | Signature | Description |
|----------|-----------|-------------|
| `scheme_codec` | `codec string` | the scheme (`text_chars 64 is_scheme_char`) |
| `segment_codec` | `codec string` | a path segment (`text_chars 1024 is_pchar`) |
| `path_codec` | `codec (list string)` | the slash-separated path (`/a/b`; empty path = empty bytes) |
| `query_pair_codec` | `codec query_param` | a `key=value` pair |
| `query_codec` | `codec query` | the `&`-separated query (`sep_by1`) |
| `ipv6_host` | `codec uri_host` | the bracketed IPv6 host |
| `ipv4_host` | `codec uri_host` | the dotted-decimal IPv4 host |
| `domain_host` | `codec uri_host` | the DNS registered name (carries `fully_qualified`) |
| `host_codec` | `codec uri_host` | `choice ipv6_host (choice ipv4_host domain_host)` |
| `port_codec` | `codec int` | the decimal port 0..65535 (`digits_to_int 5`) |
| `userinfo_codec` | `codec string` | the `userinfo` run |
| `authority_codec` | `codec authority` | `[userinfo @] host [: port]` |
| `uri_codec` | `codec uri` | the whole RFC 3986 generic URI |

## Delimiters

| Constant | Byte | Description |
|----------|------|-------------|
| `colon` | `0x3A` | `:` |
| `slash` | `0x2F` | `/` |
| `question` | `0x3F` | `?` |
| `hash` | `0x23` | `#` |
| `at_sign` | `0x40` | `@` |
| `equals` | `0x3D` | `=` |
| `ampersand` | `0x26` | `&` |

## Smart constructors / views

| Function | Signature | Description |
|----------|-----------|-------------|
| `encode_uri` | `uri -> byte_seq` | serialize a URI to bytes |
| `decode_uri` | `byte_seq -> option uri` | parse bytes into a URI |
| `uri_of_string` | `string -> option uri` | parse a text string (rejects non-ASCII) |
| `string_of_uri` | `uri -> string` | serialize to text |
| `authority_of_string` | `string -> option authority` | parse an authority text string |
| `host_of_string` | `string -> option uri_host` | parse a host text string |
| `ascii_bytes_to_string` | `list byte -> string` | ASCII byte list to string |
| `string_to_ascii_bytes` | `string -> option (list byte)` | string to bytes (`None` on non-ASCII) |

## Pulse leaf

| Function | Signature | Description |
|----------|-----------|-------------|
| `encode_scheme` | `fn scheme (A.array U8.t) (U32.t) -> U32.t` | write the tag byte, returns `1` |
| `decode_scheme` | `fn (A.array U8.t) (U32.t) -> opt_uri_scheme` | read the tag byte |
| `lemma_pulse_scheme_roundtrip` | Pulse `fn` | encode then decode recovers the tag |
| `tag_to_type` | `U8.t -> option uri_scheme` | the pure tag-byte inverse |
| `tag_byte_of` | `uri_scheme -> U8.t` | the pure scheme → tag mapping (`noextract`) |

## Lemmas

| Lemma | Proves |
|-------|--------|
| `lemma_uri_roundtrip` | `uri_codec.dec (enc u ++ empty) == Inr (u, \|enc u\|)` for a well-formed `uri` |
| `lemma_encode_uri_roundtrip` | `decode_uri (encode_uri u) == Some u` |
| `lemma_scheme_nonempty` | a well-formed `uri` has a non-empty scheme |
| `lemma_tag_roundtrip` | `tag_to_type (tag_byte_of t) == Some t` (`noextract`) |
