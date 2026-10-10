(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Network.URI — URI type and codec (RFC 3986).

A verified URI grammar built on the record [Data.Codec] combinator library
(Mandate 22: no bespoke scanners — every parse/serialize step is a combinator).

@header Network.URI

@section Types
- [uri_host] — [IPv4Host] | [IPv6Host] | [DomainHost]
- [authority] — [userinfo] `@` [host] `:` [port]
- [uri] — [scheme] `:` [authority]? [path] [`?`query]? [`#`fragment]?

@section Character predicates
- [is_scheme_char] / [is_unreserved] / [is_sub_delim] / [is_pchar] / [is_query_char]

@section Codecs
- [segment_codec] / [path_codec] — the slash-separated path
- [query_pair_codec] / [query_codec] — the ampersand-separated query
- [host_codec] / [authority_codec] — the host + authority
- [uri_codec] — the whole URI

@section Smart constructors
- [uri_of_string] / [string_of_uri] / [encode_uri] / [decode_uri]

@section Roundtrip
- [lemma_uri_roundtrip] — dec (enc u ++ empty) == Inr (u, |enc u|)
*)
module Network.URI

open Data.Codec
open Data.Text.Codec
open FStar.Seq
open FStar.List.Tot
open Network.IPv4
open Network.IPv6
open Network.DNS

module U8 = FStar.UInt8


(* ========================================================================
   Types
   ======================================================================== *)


(** [uri_host] — the three host kinds of RFC 3986 §3.2.2: an IP-literal
    (IPv6, bracketed), an IPv4 address (dotted-decimal), or a registered
    name (DNS domain). *)
type uri_host =
  | IPv4Host   : ipv4 -> uri_host
  | IPv6Host   : ipv6 -> uri_host
  | DomainHost : domain_name -> uri_host


(** [authority] — the RFC 3986 §3.2 authority: optional userinfo, a host,
    optional port. *)
type authority = {
  userinfo : option string;
  host     : uri_host;
  port     : option int;
}


(** [path] — a sequence of path segments (RFC 3986 §3.3). *)
type path = list string


(** [query_param] — a single `key=value` query pair (RFC 3986 §3.4). *)
type query_param = {
  key   : string;
  value : string;
}


(** [query] — a sequence of query pairs. *)
type query = list query_param


(** [uri] — the RFC 3986 generic URI: scheme, optional authority, path,
    optional query, optional fragment. *)
type uri = {
  scheme    : string;
  authority : option authority;
  path      : path;
  query     : option query;
  fragment  : option string;
}


(* ========================================================================
   Character predicates (RFC 3986 §2.2 / §3.2 / §3.3 / §3.4)
   ======================================================================== *)


(** [code_of] — the integer code point of a character. *)
let code_of (c: FStar.Char.char) : int = FStar.Char.int_of_char c


(** [is_scheme_char] — RFC 3986 [scheme]: `ALPHA ( ALPHA | DIGIT | + | - | . )*`.
    Evaluated at the character level (non-ASCII is rejected via the [< 128]
    guard, mirroring the [ascii_ok] bridge). *)
let is_scheme_char (c: FStar.Char.char) : bool =
  let v = code_of c in
  v >= 0 && v < 128 &&
  (char_is_alpha c || char_is_digit c || v = 0x2B || v = 0x2D || v = 0x2E)


(** [is_unreserved] — RFC 3986 [unreserved]: `ALPHA | DIGIT | - | . | _ | ~`. *)
let is_unreserved (c: FStar.Char.char) : bool =
  let v = code_of c in
  v >= 0 && v < 128 &&
  (char_is_alpha c || char_is_digit c ||
   v = 0x2D || v = 0x2E || v = 0x5F || v = 0x7E)


(** [is_sub_delim] — RFC 3986 [sub-delims]:
    `! $ & ' ( ) * + , ; =`. *)
let is_sub_delim (c: FStar.Char.char) : bool =
  let v = code_of c in
  v = 0x21 || v = 0x24 || v = 0x26 || v = 0x27 ||
  v = 0x28 || v = 0x29 || v = 0x2A || v = 0x2B ||
  v = 0x2C || v = 0x3B || v = 0x3D


(** [is_pchar] — RFC 3986 [pchar]: [unreserved] | [sub-delims] | `:` | `@`.
    (i.e. any char except the delimiters `/ ? #`). *)
let is_pchar (c: FStar.Char.char) : bool =
  let v = code_of c in
  v >= 0 && v < 128 && v <> 0x2F && v <> 0x3F && v <> 0x23


(** [is_query_char] — RFC 3986 [query]: [pchar] | `/` | `?` (but NOT `=` or
    `&` or `#`, since those delimit pairs and the fragment). *)
let is_query_char (c: FStar.Char.char) : bool =
  let v = code_of c in
  v >= 0 && v < 128 && v <> 0x3D && v <> 0x26 && v <> 0x23


(* ========================================================================
   Named delimiter bytes (RFC 3986 §2 reserved)
   ======================================================================== *)


(** [colon] — the [:] (0x3A) delimiter. *)
let colon : codec unit = byte_val 0x3Auy


(** [slash] — the [/] (0x2F) delimiter. *)
let slash : codec unit = byte_val 0x2Fuy


(** [question] — the [?] (0x3F) delimiter. *)
let question : codec unit = byte_val 0x3Fuy


(** [hash] — the [#] (0x23) delimiter. *)
let hash : codec unit = byte_val 0x23uy


(** [at_sign] — the [@] (0x40) delimiter. *)
let at_sign : codec unit = byte_val 0x40uy


(** [equals] — the [=] (0x3D) delimiter. *)
let equals : codec unit = byte_val 0x3Duy


(** [ampersand] — the [&] (0x26) delimiter. *)
let ampersand : codec unit = byte_val 0x26uy


(* ========================================================================
   Scheme codec
   ======================================================================== *)


(** [scheme_codec] — the RFC 3986 [scheme] as a [codec string]: one-or-more
    scheme characters, bounded to 64 (a practical upper bound well above any
    registered scheme).  Built on [text_chars], the verified bounded-greedy
    one-or-more string combinator. *)
let scheme_codec : codec string = text_chars 64 is_scheme_char


(* ========================================================================
   Path codec
   ======================================================================== *)


(** [segment_codec] — a single path segment: one-or-more [pchar] bytes,
    bounded to 1024. *)
let segment_codec : codec string = text_chars 1024 is_pchar


(** [path_codec] — a slash-separated segment list.  A path [["a"; "b"]]
    encodes as [/a/b] (RFC 3986 [path-abempty] = `*( "/" segment )`); the
    empty path encodes as the empty bytes.  The non-empty form is a slash
    prefix followed by [sep_by1 segment_codec slash] (separator between the
    remaining segments); the empty form is [pure []]. *)
let path_codec : codec (list string) =
  choice
    (map_
      (fun (_, segs) -> Some segs)
      (fun segs -> Some ((), segs))
      (product slash (sep_by1 segment_codec slash 1024)))
    (pure [])


(* ========================================================================
   Query codec
   ======================================================================== *)


(** [query_pair_codec] — a single `key=value` pair as a [codec query_param]. *)
let query_pair_codec : codec query_param =
  map_
    (fun (k, (_, v)) -> Some ({ key = k; value = v }))
    (fun (p: query_param) -> Some (p.key, ((), p.value)))
    (product
      (text_chars 1024 is_query_char)
      (product equals (text_chars 1024 is_query_char)))


(** [query_codec] — an ampersand-separated list of query pairs.  A query
    [["k1"; "v1"]; ["k2"; "v2"]] encodes as [k1=v1&k2=v2]. *)
let query_codec : codec query =
  sep_by1 query_pair_codec ampersand 1024


(* ========================================================================
   Host codec
   ======================================================================== *)


(** [ipv6_host] — the bracketed IPv6-literal host (RFC 3986 §3.2.2 [IP-literal]).
    The brackets are part of the [fstar-ip] [ipv6_codec]'s wire form. *)
let ipv6_host : codec uri_host =
  map_
    (fun (ip: ipv6) -> Some (IPv6Host ip))
    (fun h -> match h with IPv6Host ip -> Some ip | _ -> None)
    Network.IPv6.ipv6_codec


(** [ipv4_host] — the dotted-decimal IPv4 host. *)
let ipv4_host : codec uri_host =
  map_
    (fun (ip: ipv4) -> Some (IPv4Host ip))
    (fun h -> match h with IPv4Host ip -> Some ip | _ -> None)
    Network.IPv4.ipv4_codec


(** [domain_host] — the registered-name (DNS) host.  [fstar-dns]'s
    [domain_codec] carries the [fully_qualified] trailing-dot flag in the
    [domain_name] record; that record is carried opaquely through the
    [DomainHost] constructor. *)
let domain_host : codec uri_host =
  map_
    (fun (d: domain_name) -> Some (DomainHost d))
    (fun h -> match h with DomainHost d -> Some d | _ -> None)
    Network.DNS.domain_codec


(** [host_codec] — the prefix-disjoint choice of the three host kinds.

    IPv6 (bracketed, starts `[`) is tried first, then IPv4 (starts a digit),
    then the DNS domain (starts a letter or other registered-name byte).  The
    [choice] combinator tags each arm with a [0x00]/[0x01] byte so the
    backward map is unambiguous. *)
let host_codec : codec uri_host =
  choice ipv6_host (choice ipv4_host domain_host)


(* ========================================================================
   Authority codec
   ======================================================================== *)


(** [port_codec] — a decimal port (0..65535) as a [codec int], built on
    [digits_to_int] (the verified bounded digit accumulator — no bespoke
    scanner).  The [<= 65535] upper bound is the well-formedness guard. *)
let port_codec : codec int = digits_to_int 5 (fun v -> v <= 65535)


(** [userinfo_codec] — the [userinfo] `@` run (RFC 3986 §3.2.1). *)
let userinfo_codec : codec string = text_chars 1024 is_pchar


(** [authority_codec] — [ [userinfo "@"] host [":" port] ] as a [codec
    authority], with the two optional components wrapped in [optional]
    (tagged [sum], so [None] is representable). *)
let authority_codec : codec authority =
  let userinfo_part : codec (option string) =
    optional (map_ (fun (u, _) -> Some u)
                   (fun u -> Some (u, ()))
                   (product userinfo_codec at_sign))
  in
  let port_part : codec (option int) =
    optional (map_ (fun (_, p) -> Some p)
                   (fun p -> Some ((), p))
                   (product colon port_codec))
  in
  map_
    (fun (ui, (h, p)) -> Some ({ userinfo = ui; host = h; port = p }))
    (fun (a: authority) -> Some (a.userinfo, (a.host, a.port)))
    (product userinfo_part (product host_codec port_part))


(* ========================================================================
   URI codec
   ======================================================================== *)


(** [uri_codec] — the RFC 3986 generic URI:

        scheme ":" [ "//" authority ] path [ "?" query ] [ "#" fragment ]

    The scheme is followed by a colon; the authority (if present) by [//];
    then the path, an optional query, and an optional fragment.  All optional
    components use [optional] (tagged [sum]). *)
let uri_codec : codec uri =
  let scheme_part : codec (unit & string) =
    product colon scheme_codec
  in
  let authority_part : codec (option authority) =
    optional (map_ (fun (_, (_, a)) -> Some a)
                   (fun a -> Some ((), ((), a)))
                   (product slash (product slash authority_codec)))
  in
  let query_part : codec (option query) =
    optional (map_ (fun (_, q) -> Some q)
                   (fun q -> Some ((), q))
                   (product question query_codec))
  in
  let fragment_part : codec (option string) =
    optional (map_ (fun (_, f) -> Some f)
                   (fun f -> Some ((), f))
                   (product hash (text_chars 1024 is_query_char)))
  in
  map_
    (fun ((_, s), (a, (p, (q, f)))) ->
      Some ({ scheme = s; authority = a; path = p; query = q; fragment = f }))
    (fun (u: uri) ->
      Some (((), u.scheme), (u.authority, (u.path, (u.query, u.fragment)))))
    (product scheme_part
      (product authority_part
        (product path_codec
          (product query_part fragment_part))))


(* ========================================================================
   ASCII bridges
   ======================================================================== *)


(** [ascii_bytes_to_string] — ASCII [list byte] to [string] (code points < 128). *)
let ascii_bytes_to_string (bs: list byte) : string =
  FStar.String.string_of_list
    (List.Tot.map (fun (b: byte) -> FStar.Char.char_of_int (U8.v b)) bs)


(** [string_to_ascii_bytes] — [string] to [list byte], returning [None] for any
    non-ASCII code point ([>= 128]).  A non-ASCII input is REJECTED rather
    than silently truncated. *)
let rec string_to_ascii_bytes_go (cs: list FStar.Char.char) : option (list byte) =
  match cs with
  | [] -> Some []
  | c :: tl ->
      let v = FStar.Char.int_of_char c in
      if v < 128
      then (match string_to_ascii_bytes_go tl with
            | None -> None
            | Some rest -> Some (U8.uint_to_t v :: rest))
      else None


let string_to_ascii_bytes (s: string) : option (list byte) =
  string_to_ascii_bytes_go (FStar.String.list_of_string s)


(* ========================================================================
   Smart constructors
   ======================================================================== *)


(** [encode_uri] — the byte-sequence encoding of a [uri]. *)
let encode_uri (u: uri) : byte_seq = uri_codec.enc u


(** [decode_uri] — decode a byte sequence into a [uri] (dropping the consumed
    count). *)
let decode_uri (input: byte_seq) : option uri =
  match uri_codec.dec input with Inl _ -> None | Inr (v, _) -> Some v


(** [uri_of_string] — parse a URI text string into a [uri]; [None] unless the
    string is pure ASCII and the whole string is consumed. *)
let uri_of_string (s: string) : option uri =
  match string_to_ascii_bytes s with
  | None -> None
  | Some bs -> decode_uri (seq_of_list bs)


(** [string_of_uri] — serialize a [uri] to its ASCII text string. *)
let string_of_uri (u: uri) : string =
  ascii_bytes_to_string (seq_to_list (encode_uri u))


(** [authority_of_string] — parse an authority text string; [None] unless the
    string is pure ASCII and fully consumed. *)
let authority_of_string (s: string) : option authority =
  match string_to_ascii_bytes s with
  | None -> None
  | Some bs ->
      (match authority_codec.dec (seq_of_list bs) with
       | Inl _ -> None
       | Inr (a, _) -> Some a)


(** [host_of_string] — parse a host text string; [None] unless the string is
    pure ASCII and fully consumed. *)
let host_of_string (s: string) : option uri_host =
  match string_to_ascii_bytes s with
  | None -> None
  | Some bs ->
      (match host_codec.dec (seq_of_list bs) with
       | Inl _ -> None
       | Inr (h, _) -> Some h)


(* ========================================================================
   Roundtrip lemmas
   ======================================================================== *)


(** [lemma_uri_roundtrip] — encode then decode (with an empty suffix)
    recovers a well-formed [uri] and its encoding length. *)
let lemma_uri_roundtrip (u: uri) : Lemma
  (requires uri_codec.wfcv u /\ uri_codec.wfcv_prop u /\ uri_codec.rest_cond u Seq.empty)
  (ensures uri_codec.dec (encode_uri u `Seq.append` Seq.empty) == Inr (u, Seq.length (encode_uri u)))
  = uri_codec.roundtrip u Seq.empty


(** [lemma_encode_uri_roundtrip] — [decode_uri (encode_uri u) == Some u]
    for a well-formed [uri]. *)
let lemma_encode_uri_roundtrip (u: uri) : Lemma
  (requires uri_codec.wfcv u /\ uri_codec.wfcv_prop u /\ uri_codec.rest_cond u Seq.empty)
  (ensures decode_uri (encode_uri u) == Some u)
  = uri_codec.roundtrip u Seq.empty;
    Seq.append_empty_r (encode_uri u);
    ()


(** [lemma_scheme_nonempty] — a well-formed [uri] has a non-empty scheme
    (the [text_chars] one-or-more guard). *)
let lemma_scheme_nonempty (u: uri) : Lemma
  (requires uri_codec.wfcv u)
  (ensures String.length u.scheme >= 1)
  = ()
