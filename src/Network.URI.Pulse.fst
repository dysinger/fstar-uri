(* Copyright 2026 Department of Code LLC.
   SPDX-License-Identifier: AGPL-3.0-or-later *)

(**
Network.URI.Pulse — C-extractable URI scheme tag dispatch via Pulse + Custard.

A single URI scheme tag ([uri_scheme]) maps to one byte (HTTP `0x00`, HTTPS
`0x01`, FTP `0x02`, WS `0x03`, WSS `0x04`, Other `0xFF`).  The encode/decode
`fn`s read/write that byte in a caller-provided [Pulse.Lib.Array] of [U8.t].

Written for F* v2026.09.20 (Custard `--custard_backend C`).  Zero admits.

@header Network.URI.Pulse

@section Type
- [uri_scheme] — the six scheme tags
- [opt_uri_scheme] — the tagged decode result ([OUR_None] | [OUR_Some])

@section Encode
- [encode_scheme] — write the tag byte, return the byte count

@section Decode
- [decode_scheme] — read the tag byte

@section Roundtrip
- [lemma_pulse_scheme_roundtrip] — encode then decode preserves the tag
*)
module Network.URI.Pulse
#lang-pulse

open Pulse
open Pulse.Lib.Reference
module A = Pulse.Lib.Array
module US = FStar.SizeT
module U8 = FStar.UInt8
module U32 = FStar.UInt32
module Seq = FStar.Seq

open FStar.Seq
open FStar.Int.Cast


(* ========================================================================
   Type
   ======================================================================== *)


(** [uri_scheme] — the URI scheme tag (1 byte). *)
type uri_scheme =
  | US_HTTP
  | US_HTTPS
  | US_FTP
  | US_WS
  | US_WSS
  | US_Other


(** [opt_uri_scheme] — the decode result: [OUR_None] (an unknown tag byte) or
    [OUR_Some] of the scheme tag and the consumed byte count ([1]). *)
type opt_uri_scheme =
  | OUR_None
  | OUR_Some of (uri_scheme & U32.t)


(* ========================================================================
   Pure spec (tag_of / tag_to_type)
   ======================================================================== *)


(** [tag_byte_of] — the pure mapping [uri_scheme] → tag byte. *)
noextract
let tag_byte_of (t: uri_scheme) : U8.t =
  match t with
  | US_HTTP -> 0x00uy
  | US_HTTPS -> 0x01uy
  | US_FTP -> 0x02uy
  | US_WS -> 0x03uy
  | US_WSS -> 0x04uy
  | US_Other -> 0xFFuy


(** [tag_to_type] — the pure inverse: tag byte → [uri_scheme] option. *)
noextract
let tag_to_type (b: U8.t) : option uri_scheme =
  if U8.eq b 0x00uy then Some US_HTTP
  else if U8.eq b 0x01uy then Some US_HTTPS
  else if U8.eq b 0x02uy then Some US_FTP
  else if U8.eq b 0x03uy then Some US_WS
  else if U8.eq b 0x04uy then Some US_WSS
  else if U8.eq b 0xFFuy then Some US_Other
  else None


(** [lemma_tag_roundtrip] — [tag_to_type (tag_byte_of t) == Some t]. *)
noextract
let lemma_tag_roundtrip (t: uri_scheme) : Lemma
  (ensures tag_to_type (tag_byte_of t) == Some t)
  = match t with
    | US_HTTP -> ()
    | US_HTTPS -> ()
    | US_FTP -> ()
    | US_WS -> ()
    | US_WSS -> ()
    | US_Other -> ()


(* ========================================================================
   Encode
   ======================================================================== *)


(** [encode_scheme] — write the scheme tag byte into [buf] at [off].

    Only [buf[off]] changes; every other byte of [buf] is preserved (see the
    [ensures]).  Returns the number of bytes written ([1]).

    @param s The scheme tag.
    @param buf The destination buffer (holds a byte at [off]).
    @param off The write offset.
    @returns [1ul]. *)
fn encode_scheme (s: uri_scheme) (buf: A.array U8.t) (off: U32.t)
    (#b0: erased (Seq.seq U8.t))
    requires
      A.pts_to buf b0 **
      pure (U32.v off < A.length buf /\
            Seq.length b0 == A.length buf)
    returns w: U32.t
    ensures
      exists* (b1: Seq.seq U8.t).
        A.pts_to buf b1 **
        pure (Seq.length b1 == A.length buf /\
              Seq.length b0 == A.length buf /\
              U32.v off < A.length buf /\
              Seq.index b1 (U32.v off) == tag_byte_of s /\
              (forall (j: nat). j <> U32.v off /\ j < Seq.length b1 ==>
                 Seq.index b1 j == Seq.index b0 j) /\
              w == 1ul)
{
  A.pts_to_len buf;
  let joff = US.uint32_to_sizet off;
  let tag = tag_byte_of s;
  buf.(joff) <- tag;
  1ul
}


(* ========================================================================
   Decode
   ======================================================================== *)


(** [decode_scheme] — read the scheme tag byte at [off].

    @param buf The source buffer.
    @param off The read offset.
    @returns [OUR_Some (tag, 1)] for a known tag byte, else [OUR_None]. *)
fn decode_scheme (buf: A.array U8.t) (off: U32.t)
    (#b0: erased (Seq.seq U8.t))
    requires
      A.pts_to buf b0 **
      pure (U32.v off < A.length buf /\
            Seq.length b0 == A.length buf)
    returns r: opt_uri_scheme
    ensures
      A.pts_to buf b0 **
      pure (Seq.length b0 == A.length buf /\
            U32.v off < A.length buf /\
            (let tag = Seq.index b0 (U32.v off) in
             let opt = tag_to_type tag in
             (match opt with
              | Some t -> r == OUR_Some (t, 1ul)
              | None -> r == OUR_None)))
{
  A.pts_to_len buf;
  let joff = US.uint32_to_sizet off;
  let tag = buf.(joff);
  if (U8.eq tag 0x00uy) { OUR_Some (US_HTTP, 1ul) }
  else if (U8.eq tag 0x01uy) { OUR_Some (US_HTTPS, 1ul) }
  else if (U8.eq tag 0x02uy) { OUR_Some (US_FTP, 1ul) }
  else if (U8.eq tag 0x03uy) { OUR_Some (US_WS, 1ul) }
  else if (U8.eq tag 0x04uy) { OUR_Some (US_WSS, 1ul) }
  else if (U8.eq tag 0xFFuy) { OUR_Some (US_Other, 1ul) }
  else { OUR_None }
}


(* ========================================================================
   Roundtrip
   ======================================================================== *)


(** [lemma_pulse_scheme_roundtrip] — encode then decode preserves the scheme.

    @param s The scheme tag.
    @param buf The buffer (holds a byte at [off]).
    @param off The offset.
    @returns [(1ul, OUR_Some (s, 1ul))] — encode then decode recovers the tag. *)
fn lemma_pulse_scheme_roundtrip (s: uri_scheme) (buf: A.array U8.t) (off: U32.t)
    (#b0: erased (Seq.seq U8.t))
    requires
      A.pts_to buf b0 **
      pure (U32.v off < A.length buf /\
            Seq.length b0 == A.length buf)
    returns res: (U32.t & opt_uri_scheme)
    ensures
      exists* (b1: Seq.seq U8.t).
        A.pts_to buf b1 **
        pure (res == (1ul, OUR_Some (s, 1ul)))
{
  let w = encode_scheme s buf off;
  let r = decode_scheme buf off;
  (w, r)
}
