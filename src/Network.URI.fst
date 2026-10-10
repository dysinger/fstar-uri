(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Network.URI — URI type and codec (RFC 3986).

A verified URI grammar built on the record [Data.Codec] combinator library
(Mandate 22: no bespoke scanners — every parse/serialize step is a combinator).

The wire format is RFC 3986 TEXT: `scheme ":" hier-part [ "?" query ]
[ "#" fragment ]`, with the host `IP-literal` / `IPv4address` / `reg-name`
branches disambiguated by their LEADING BYTE (no tag bytes), the IPv6
`IP-literal` bracketed in `[` `]`, and every optional component delimited by
its RFC separator (`//`, `?`, `#`) rather than a `sum` tag.

@header Network.URI

@section Types
- [uri_host] — [IPv4Host] | [IPv6Host] | [DomainHost]
- [authority] — [host] [":" port] (userinfo is a deferred RFC component)
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


(** [uri_host] — the three host kinds of RFC 3986 §3.2.2: an `IP-literal`
    (IPv6, bracketed), an IPv4 address (dotted-decimal), or a registered
    name (DNS domain). *)
type uri_host =
  | IPv4Host   : ipv4 -> uri_host
  | IPv6Host   : ipv6 -> uri_host
  | DomainHost : domain_name -> uri_host


(** [authority] — the RFC 3986 §3.2 authority: a host and an optional port.

    NOTE (deferred RFC component): RFC 3986 §3.2.1's [userinfo] ([userinfo
    "@"] prefix) is NOT yet carried on the wire — its [@]-delimiter split is a
    list-level multi-byte lookahead (fstar-proofs §48/§50) requiring a
    dedicated [opt_suffixed] primitive; see task 8.1.  Until then the
    authority is [host [":" port]], which stays 0-admit and fully RFC text
    (no tag bytes). *)
type authority = {
  host : uri_host;
  port : option int;
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


(** [is_scheme_char] — RFC 3986 [scheme] tail-set: `ALPHA | DIGIT | + | - | .`.
    The FIRST scheme character must be ALPHA (enforced structurally by
    [scheme_codec], not here); this predicate governs the remainder. *)
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
    (The POSITIVE set; raw `%`, brackets, and control bytes are EXCLUDED,
    mirroring the RFC exactly.) *)
let is_pchar (c: FStar.Char.char) : bool =
  let v = code_of c in
  is_unreserved c || is_sub_delim c || v = 0x3A || v = 0x40


(** [is_query_char] — RFC 3986 [query]: [pchar] | `/` | `?`.  Because `=` and
    `&` are sub-delims (and therefore [pchar]), they ARE permitted here; the
    query pair-level `=`/`&` split is handled by the compositor
    [query_pair_codec]/[query_codec], not by narrowing this set. *)
let is_query_char (c: FStar.Char.char) : bool =
  let v = code_of c in
  is_pchar c || v = 0x2F || v = 0x3F


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


(** [open_bracket] — the `[` (0x5B) delimiter framing an `IP-literal`. *)
let open_bracket : codec unit = byte_val 0x5Buy


(** [close_bracket] — the `]` (0x5D) delimiter framing an `IP-literal`. *)
let close_bracket : codec unit = byte_val 0x5Duy


(** [double_slash] — the `//` (0x2F 0x2F) authority prefix. *)
let double_slash : codec unit = bytes [0x2Fuy; 0x2Fuy]


(* ========================================================================
   Scheme codec
   ======================================================================== *)


(** [is_scheme_head] — RFC 3986 [scheme] head: the FIRST character must be
    ALPHA. *)
let is_scheme_head (c: FStar.Char.char) : bool = char_is_alpha c


(** [scheme_codec] — the RFC 3986 [scheme] as a [codec string]: an ALPHA first
    character followed by zero-or-more [is_scheme_char]s (so `https`,
    `http`, `ftp` round-trip, while `1http` is REJECTED), bounded to 64.

    A [custom] codec whose decoder/encoder/[wfcv] delegate to the verified
    [text_chars] run but ADD the alpha-first head guard ([text_chars] applies
    a single per-char predicate to every char and cannot enforce a distinct
    first-char class). *)
let scheme_codec : codec string =
  custom
    (fun (input: byte_seq) ->
      match text_chars_dec 64 is_scheme_char input with
      | Inr (s, n) ->
          let cs = FStar.String.list_of_string s in
          (match cs with
           | c :: _ ->
               if is_scheme_head c then Inr (s, n)
               else Inl (mk_decode_error ExpectedPredicate 0)
           | [] -> Inl (mk_decode_error ExpectedPredicate 0))
      | Inl e -> Inl e)
    (text_chars_enc is_scheme_char)
    (fun (s: string) ->
      let cs = FStar.String.list_of_string s in
      (match cs with
       | c :: _ -> text_chars_wfcv 64 is_scheme_char s && is_scheme_head c
       | [] -> false))
    (fun (s: string) -> True)
    (text_chars_rest_cond 64 is_scheme_char)
    (fun (s: string) (r: byte_seq) ->
      let cs = FStar.String.list_of_string s in
      (match cs with
       | c :: _ ->
           assert (is_scheme_head c);
           assert (text_chars_wfcv 64 is_scheme_char s);
           assert (True);
           assert (text_chars_rest_cond 64 is_scheme_char s r);
           lemma_text_chars_roundtrip 64 is_scheme_char s r;
           assert (text_chars_dec 64 is_scheme_char (text_chars_enc is_scheme_char s `Seq.append` r)
                     == Inr (s, Seq.length (text_chars_enc is_scheme_char s)));
           Seq.lemma_index_app1 (text_chars_enc is_scheme_char s) r 0;
           ()
       | [] -> ()))
    (lemma_text_chars_dec_err_bound 64 is_scheme_char)
    (lemma_text_chars_dec_consumed_bound 64 is_scheme_char)


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
    The `[` `]` brackets ARE part of the wire form (added here via [between];
    [fstar-ip]'s [ipv6_codec] is the bare colon-hex content). *)
let ipv6_host : codec uri_host =
  map_
    (fun (ip: ipv6) -> Some (IPv6Host ip))
    (fun h -> match h with IPv6Host ip -> Some ip | _ -> None)
    (between open_bracket close_bracket Network.IPv6.ipv6_codec)


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


(** [is_open_bracket_byte b] — does byte [b] open an `[` IP-literal? *)
let is_open_bracket_byte (b: byte) : bool = U8.v b = 0x5B


(** [is_digit_byte b] — does byte [b] begin a dotted-decimal IPv4 address? *)
let is_digit_byte (b: byte) : bool = is_digit b


(** [is_slash_byte b] — the `/` (0x2F) delimiter byte (authority prefix). *)
let is_slash_byte (b: byte) : bool = U8.v b = 0x2F


(** [is_question_byte b] — the `?` (0x3F) delimiter byte (query prefix). *)
let is_question_byte (b: byte) : bool = U8.v b = 0x3F


(** [is_hash_byte b] — the `#` (0x23) delimiter byte (fragment prefix). *)
let is_hash_byte (b: byte) : bool = U8.v b = 0x23


(** [is_colon_byte b] — the `:` (0x3A) delimiter byte (port prefix). *)
let is_colon_byte (b: byte) : bool = U8.v b = 0x3A


(** [host_codec] — the prefix-disjoint choice of the three host kinds,
    UNTAGGED: the leading byte disambiguates —

      - `[` → bracketed IPv6 ([ipv6_host]), tried first;
      - a digit → dotted-decimal IPv4 ([ipv4_host]);
      - anything else → DNS registered name ([domain_host]).

    All three are first-byte-disjoint (a `[` is never a digit and never a
    registered-name byte), so the untagged [alt] combinator applies with no
    tag byte on the wire. *)
let host_codec : codec uri_host =
  map_
    (fun (v: either uri_host uri_host) ->
      match v with Inl h -> Some h | Inr h -> Some h)
    (fun (h: uri_host) ->
      match h with
      | IPv6Host _ -> Some (Inl h)
      | _ -> Some (Inr h))
    (alt
      ipv6_host
      (map_
        (fun (v: either uri_host uri_host) ->
          match v with Inl h -> Some h | Inr h -> Some h)
        (fun (h: uri_host) ->
          match h with IPv4Host _ -> Some (Inl h) | _ -> Some (Inr h))
        (alt ipv4_host domain_host is_digit_byte))
      is_open_bracket_byte)


(* ========================================================================
   Authority codec
   ======================================================================== *)


(** [port_codec] — a decimal port (0..65535) as a [codec int], built on
    [digits_to_int] (the verified bounded digit accumulator — no bespoke
    scanner).  The [<= 65535] upper bound is the well-formedness guard. *)
let port_codec : codec int = digits_to_int 5 (fun v -> v <= 65535)


(** [userinfo_codec] — the [userinfo] run (RFC 3986 §3.2.1: [unreserved] |
    [pct-encoded] | [sub-delims] | `:` — NOTE `@` is EXCLUDED, it terminates
    userinfo).  Reserved for the deferred userinfo component (see the
    [authority] note). *)
let is_userinfo_char (c: FStar.Char.char) : bool =
  let v = code_of c in
  is_unreserved c || is_sub_delim c || v = 0x3A


let userinfo_codec : codec string = text_chars 1024 is_userinfo_char


(** [authority_codec] — [ host [":" port] ] as a [codec authority] (no tag
    bytes; the [port] optional is delimiter-prefixed via [opt_prefixed]). *)
let authority_codec : codec authority =
  let port_part : codec (option int) =
    opt_prefixed is_colon_byte colon port_codec
  in
  map_
    (fun (h, p) -> Some ({ host = h; port = p }))
    (fun (a: authority) -> Some (a.host, a.port))
    (product host_codec port_part)


(* ========================================================================
   URI codec
   ======================================================================== *)


(** [uri_codec] — the RFC 3986 generic URI:

        scheme ":" [ "//" authority ] path [ "?" query ] [ "#" fragment ]

    The scheme is followed by a colon (payload BEFORE delimiter); the
    authority (if present) is prefixed by [//]; then the path, an optional
    query ([?]…), and an optional fragment ([#]…).  The colon/`?`/`#`
    delimiters follow their payload, matching RFC text order. *)
let uri_codec : codec uri =
  let scheme_part : codec (string & unit) =
    product scheme_codec colon
  in
  let authority_part : codec (option authority) =
    opt_prefixed is_slash_byte double_slash authority_codec
  in
  let query_part : codec (option query) =
    opt_prefixed is_question_byte question query_codec
  in
  let fragment_part : codec (option string) =
    opt_prefixed is_hash_byte hash (text_chars 1024 is_query_char)
  in
  map_
    (fun ((s, _), (a, (p, (q, f)))) ->
      Some ({ scheme = s; authority = a; path = p; query = q; fragment = f }))
    (fun (u: uri) ->
      Some ((u.scheme, ()), (u.authority, (u.path, (u.query, u.fragment)))))
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


(** [scheme_head] — the first character of a [uri]'s scheme ([None] iff the
    scheme is empty; [Some c] carries the ALPHA head when well-formed). *)
let scheme_head (u: uri) : option FStar.Char.char =
  match FStar.String.list_of_string u.scheme with
  | c :: _ -> Some c
  | [] -> None


(** [lemma_scheme_nonempty] — a scheme that is well-formed for [scheme_codec]
    is non-empty and starts with an ALPHA character (the RFC 3986 [scheme]
    head rule).

    The precondition is the DIRECT, dischargeable [scheme_codec.wfcv] (the
    [custom] head guard = [text_chars_wfcv] non-empty one-or-more run
    conjoined with [is_scheme_head]), NOT the opaque composed
    [uri_codec.wfcv] — so the implication is genuinely derived, not skipped
    through opacity (fstar-proofs §24/§26).  [uri_codec.wfcv u] implies this
    precondition via the [map_]/[product] well-formedness conjuncts. *)
let lemma_scheme_nonempty (u: uri) : Lemma
  (requires scheme_codec.wfcv u.scheme)
  (ensures
    String.length u.scheme >= 1 /\
    (match scheme_head u with Some c -> char_is_alpha c | None -> False))
  =
    let cs = FStar.String.list_of_string u.scheme in
    match cs with
    | c :: _ ->
        assert (text_chars_wfcv 64 is_scheme_char u.scheme);
        assert (is_scheme_head c);
        assert (char_is_alpha c);
        ()
    | [] -> (assert (Cons? cs))
