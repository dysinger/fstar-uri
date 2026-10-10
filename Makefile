# Copyright 2026 Department of Code LLC.
# SPDX-License-Identifier: AGPL-3.0-or-later

# F* dev-loop build (verify).
#
# Usage: nix develop, then `make check`.
#
# FSTAR_CHECKED / CODEC_SRC / CODEC_CHECKED / TEXT_SRC / TEXT_CHECKED /
# BASEN_SRC / BASEN_CHECKED / IP_SRC / IP_CHECKED / DNS_SRC / DNS_CHECKED are
# exported by the flake devShell (see flake.nix shellHook).  Override them
# here if needed.

# ── Tools ──────────────────────────────────────────────────────────

OUT ?= out

FSTAR ?= fstar.exe

CODEC_SRC ?= $(error CODEC_SRC is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
CODEC_CHECKED ?= $(error CODEC_CHECKED is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
TEXT_SRC ?= $(error TEXT_SRC is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
TEXT_CHECKED ?= $(error TEXT_CHECKED is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
BASEN_SRC ?= $(error BASEN_SRC is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
BASEN_CHECKED ?= $(error BASEN_CHECKED is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
IP_SRC ?= $(error IP_SRC is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
IP_CHECKED ?= $(error IP_CHECKED is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
DNS_SRC ?= $(error DNS_SRC is not set; run \`nix develop\` (or export it yourself) before \`make check\`)
DNS_CHECKED ?= $(error DNS_CHECKED is not set; run \`nix develop\` (or export it yourself) before \`make check\`)

FLIB := $(shell $(FSTAR) --locate_lib 2>/dev/null || echo /none)
ULIB := $(FLIB)/ulib

PULSE_DIRS := $(FLIB)/pulse/common\
  $(FLIB)/pulse/common.checked\
  $(FLIB)/pulse/pulse/lib\
  $(FLIB)/pulse/pulse.checked

FSTAR_FLAGS = --no_default_includes \
  --include $(ULIB) \
  $(foreach d,$(PULSE_DIRS),--include $(d)) \
  --include $(CODEC_SRC)/src \
  --include $(TEXT_SRC)/src \
  --include $(BASEN_SRC)/src \
  --include $(IP_SRC)/src \
  --include $(DNS_SRC)/src \
  --include ./src

# ── F* verification ───────────────────────────────────────────────

SRC_MODS := Network.URI Network.URI.Pulse

ALREADY_CACHED := Prims,FStar,Pulse.Nolib,Pulse.Lib,Pulse.Class,PulseCore

TST_MODS := Network.URI.Test.Integration

.PHONY: check clean

check: $(addprefix $(OUT)/checked/,$(addsuffix .fst.checked,$(SRC_MODS))) \
       $(addprefix $(OUT)/checked/,$(addsuffix .fst.checked,$(TST_MODS)))

$(OUT)/checked/%.fst.checked: src/%.fst
	@mkdir -p $(OUT)/checked
	@test -n "$(FSTAR_CHECKED)" || { \
	  echo "ERROR: FSTAR_CHECKED is not set; run \`nix develop\` (or export it yourself) before \`make check\`" >&2; \
	  exit 1; }
	@cp $(FSTAR_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(CODEC_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(TEXT_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(BASEN_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(IP_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(DNS_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@echo "=== $* ==="
	$(FSTAR) $(FSTAR_FLAGS) \
	  --z3rlimit 120 \
	  --already_cached $(ALREADY_CACHED) \
	  --cache_checked_modules --cache_dir $(OUT)/checked \
	  --odir $(OUT)/checked $<

$(OUT)/checked/%.fst.checked: test/%.fst
	@mkdir -p $(OUT)/checked
	@test -n "$(FSTAR_CHECKED)" || { \
	  echo "ERROR: FSTAR_CHECKED is not set; run \`nix develop\` first" >&2; \
	  exit 1; }
	@cp $(FSTAR_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(CODEC_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(TEXT_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(BASEN_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(IP_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@cp $(DNS_CHECKED)/*.checked $(OUT)/checked/ 2>/dev/null || true
	@echo "=== $* ==="
	$(FSTAR) $(FSTAR_FLAGS) --include ./test \
	  --z3rlimit 120 \
	  --already_cached $(ALREADY_CACHED) \
	  --cache_checked_modules --cache_dir $(OUT)/checked \
	  --odir $(OUT)/checked $<

# ── Clean ─────────────────────────────────────────────────────────────

clean:
	rm -rf $(OUT) cache result result-*
