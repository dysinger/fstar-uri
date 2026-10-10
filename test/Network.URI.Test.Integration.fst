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
