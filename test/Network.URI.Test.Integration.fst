(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Network.URI.Test.Integration — 100% coverage anchors + RFC 3986 vectors.

Anchors (bare [let _x = f] references) every public value/lemma/[fn] in
[Network.URI] and [Network.URI.Pulse], so a deleted/renamed definition fails
verification here.  Only type declarations and [noextract] spec helpers are
exempt (they cannot be value-anchored).  See the `.pi` fstar coverage-audit
recipe (fstar-2026.09.20 §7/§9).

@header Network.URI.Test.Integration
*)
module Network.URI.Test.Integration

open Network.URI
open Network.URI.Pulse
open Network.DNS
open Data.Codec
open FStar.Seq


(* ========================================================================
   Coverage anchors — Network.URI (value + lemma)
   ======================================================================== *)


let _is_scheme_char = is_scheme_char
let _is_unreserved = is_unreserved
let _is_sub_delim = is_sub_delim
let _is_pchar = is_pchar
let _is_query_char = is_query_char
let _code_of = code_of

let _colon = colon
let _slash = slash
let _question = question
let _hash = hash
let _at_sign = at_sign
let _equals = equals
let _ampersand = ampersand
let _open_bracket = open_bracket
let _close_bracket = close_bracket
let _double_slash = double_slash
let _is_scheme_head = is_scheme_head
let _is_open_bracket_byte = is_open_bracket_byte
let _is_digit_byte = is_digit_byte
let _is_slash_byte = is_slash_byte
let _is_question_byte = is_question_byte
let _is_hash_byte = is_hash_byte
let _is_colon_byte = is_colon_byte

let _scheme_codec = scheme_codec
let _segment_codec = segment_codec
let _path_codec = path_codec
let _query_pair_codec = query_pair_codec
let _query_codec = query_codec

let _ipv6_host = ipv6_host
let _ipv4_host = ipv4_host
let _domain_host = domain_host
let _host_codec = host_codec
let _port_codec = port_codec
let _userinfo_codec = userinfo_codec
let _is_userinfo_char = is_userinfo_char
let _authority_codec = authority_codec
let _uri_codec = uri_codec

let _ascii_bytes_to_string = ascii_bytes_to_string
let _string_to_ascii_bytes_go = string_to_ascii_bytes_go
let _string_to_ascii_bytes = string_to_ascii_bytes

let _encode_uri = encode_uri
let _decode_uri = decode_uri
let _uri_of_string = uri_of_string
let _string_of_uri = string_of_uri
let _authority_of_string = authority_of_string
let _host_of_string = host_of_string

let _lemma_uri_roundtrip = lemma_uri_roundtrip
let _lemma_encode_uri_roundtrip = lemma_encode_uri_roundtrip
let _scheme_head = scheme_head
let _lemma_scheme_nonempty = lemma_scheme_nonempty


(* ========================================================================
   Coverage anchors — Network.URI.Pulse (value + lemma)
   ======================================================================== *)


let _tag_to_type = tag_to_type
let _encode_scheme = encode_scheme
let _decode_scheme = decode_scheme
let _lemma_pulse_scheme_roundtrip = lemma_pulse_scheme_roundtrip


(* ========================================================================
   RFC 3986 concrete vectors (byte-level, [assert_norm]-reduced)
   ======================================================================== *)


(** [lemma_scheme_https_concrete] — the [https] scheme encodes to its ASCII
    bytes ([0x68 0x74 0x74 0x70 0x73]). *)
let lemma_scheme_https_concrete () : Lemma
  (ensures scheme_codec.enc "https" == seq_of_list [0x68uy; 0x74uy; 0x74uy; 0x70uy; 0x73uy])
  = assert_norm (scheme_codec.enc "https" == seq_of_list [0x68uy; 0x74uy; 0x74uy; 0x70uy; 0x73uy])


(** [www_example_com] — the domain [example.com] (non-FQ) as a concrete
    [domain_name] for the RFC vectors. *)
let www_example_com : domain_name =
  domain_of_labels
    [ { label_bytes = [0x65uy; 0x78uy; 0x61uy; 0x6Duy; 0x70uy; 0x6Cuy; 0x65uy] };
      { label_bytes = [0x63uy; 0x6Fuy; 0x6Duy] } ]
    false


(** [lemma_domain_example_com_concrete] — the [example.com] domain host
    (non-FQ) encodes to its dotted ASCII bytes. *)
let lemma_domain_example_com_concrete () : Lemma
  (ensures domain_codec.enc www_example_com
      == seq_of_list [0x65uy; 0x78uy; 0x61uy; 0x6Duy; 0x70uy; 0x6Cuy; 0x65uy;
                      0x2Euy; 0x63uy; 0x6Fuy; 0x6Duy])
  = Seq.lemma_eq_intro
      (domain_codec.enc www_example_com)
      (seq_of_list [0x65uy; 0x78uy; 0x61uy; 0x6Duy; 0x70uy; 0x6Cuy; 0x65uy;
                    0x2Euy; 0x63uy; 0x6Fuy; 0x6Duy])

(** NOTE (task 8.10 / fstar-proofs §18/§45): the FULL-URI concrete
    byte-vector ([https://example.com/], [http://a/b?q=1#frag]) is NOT
    asserted as a flat [seq_of_list] equality — the [uri_codec] is a deep
    [map_]/[product]/[opt_prefixed] composition whose [.enc] does not
    normalize under [assert_norm]/[Seq.lemma_eq_intro].  Concrete coverage is
    provided by (a) the [scheme] vector above, (b) the [domain] vector above,
    (c) the STRUCTURAL [lemma_uri_roundtrip] ([uri_codec.roundtrip]), and (d)
    the Pulse leaf roundtrip — the same documented boundary carried by the
    sibling [fstar-dns]/[fstar-mime] packages. *)
