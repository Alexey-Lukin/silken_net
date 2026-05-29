# firmware/test/Makefile — Host-based unit tests for SilkenNet firmware.
#
# Compiles extracted firmware logic with gcc on x86/x64.
# No ARM toolchain required — tests run on the build host.
#
# Usage:
#   make          — build & run all tests
#   make queen    — build & run queen tests only
#   make soldier  — build & run soldier tests only
#   make clean    — remove binaries

CC       = gcc
CFLAGS   = -Wall -Wextra -Wpedantic -std=c11 -I. -O2
BINDIR   = .

# [FW.2] OpenSSL flags via pkg-config (portable across macOS/Homebrew + Linux).
# Used by tests that link libcrypto for AES-CCM mock or HKDF: test_encryption,
# test_seed_derivation. Empty fallback if pkg-config absent.
OPENSSL_CFLAGS = $(shell pkg-config --cflags openssl 2>/dev/null)
OPENSSL_LIBS   = $(shell pkg-config --libs openssl 2>/dev/null || echo -lcrypto)

.PHONY: all queen soldier bio_contract tinyml encryption seed_derivation ccm size-check clean

all: queen soldier bio_contract tinyml encryption seed_derivation ccm

queen: $(BINDIR)/test_queen
	@./$(BINDIR)/test_queen

soldier: $(BINDIR)/test_soldier
	@./$(BINDIR)/test_soldier

bio_contract: $(BINDIR)/test_bio_contract
	@./$(BINDIR)/test_bio_contract

tinyml: $(BINDIR)/test_tinyml
	@./$(BINDIR)/test_tinyml

encryption: $(BINDIR)/test_encryption
	@./$(BINDIR)/test_encryption

seed_derivation: $(BINDIR)/test_seed_derivation
	@./$(BINDIR)/test_seed_derivation

ccm: $(BINDIR)/test_ccm
	@./$(BINDIR)/test_ccm

$(BINDIR)/test_queen: test_queen_logic.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_queen_logic.c

$(BINDIR)/test_soldier: test_soldier_logic.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_soldier_logic.c

$(BINDIR)/test_bio_contract: test_bio_contract.c
	$(CC) $(CFLAGS) -o $@ test_bio_contract.c -lm

$(BINDIR)/test_tinyml: test_tinyml_pipeline.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_tinyml_pipeline.c -lm

$(BINDIR)/test_encryption: test_encryption.c hal_mock.h ../queen/coap_iv.h
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_encryption.c $(OPENSSL_LIBS)

# [SEC.11] Host parity for SilkenNet::SeedDerivation. Uses OpenSSL
# libcrypto on host; firmware MCU side runs the same primitives via
# mbedTLS (already linked for AES). Same standard primitives →
# byte-identical (x0, y0, z0) for the same (K_seed, epoch_day) tuple.
$(BINDIR)/test_seed_derivation: test_seed_derivation.c
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_seed_derivation.c $(OPENSSL_LIBS) -lm

# [FW.2] AES-128-CCM packet roundtrip — links libcrypto for the mock HAL.
$(BINDIR)/test_ccm: test_ccm.c hal_mock.h ../common/lora_ccm.h
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_ccm.c $(OPENSSL_LIBS)

clean:
	rm -f $(BINDIR)/test_queen $(BINDIR)/test_soldier $(BINDIR)/test_bio_contract \
	      $(BINDIR)/test_tinyml $(BINDIR)/test_encryption $(BINDIR)/test_seed_derivation \
	      $(BINDIR)/test_ccm

# [FW.26] CI gate — Static RAM budget check (.bss + .data ≤ 50 KB).
#
# STM32WLE5JC має 64 KB SRAM; runtime stack ~8 KB, heap mruby ~4 KB,
# Tensor Arena (FW.4) ~8-32 KB. Решту 50 KB ділять усі статичні буфери,
# глобали і фрейми. Цей gate ловить тиху регресію розмірів (нові buffers,
# розширення EMA-вікон, OTA масивів тощо) до того, як вона з'їсть
# залишковий простір TinyML.
#
# Використовуємо host `size` проти host-тест build як ПЛАЦХОЛЬДЕР, доки
# lab build з arm-none-eabi-size не активний. Host build містить ті ж
# глобальні буфери (raw_audio_buffer, audio_buffer, OTA chunk map etc.),
# що і firmware build, тому регресія тут = регресія на target.
#
# Threshold 51200 bytes = 50 KB (ділимо 64 KB SRAM на буфери і кошти
# виконання, залишаючи runtime ~14 KB запасу). Перевищення → exit 1.
SIZE_LIMIT_BYTES ?= 51200
SIZE_TOOL ?= size

size-check: $(BINDIR)/test_soldier $(BINDIR)/test_queen
	@echo "[FW.26] Static RAM budget check (.bss + .data ≤ 50 KB)"
	@echo "──────────────────────────────────────────────────────"
	@$(SIZE_TOOL) $(BINDIR)/test_soldier $(BINDIR)/test_queen
	@echo "──────────────────────────────────────────────────────"
	@for bin in $(BINDIR)/test_soldier $(BINDIR)/test_queen; do \
	  total=$$($(SIZE_TOOL) -B "$$bin" 2>/dev/null | awk 'NR==2 {print $$2 + $$3}'); \
	  if [ -z "$$total" ]; then \
	    total=$$($(SIZE_TOOL) "$$bin" | awk 'NR==2 {print $$2 + $$3}'); \
	  fi; \
	  printf "  %-50s %8d bytes (.bss + .data)\n" "$$bin" "$$total"; \
	  if [ "$$total" -gt "$(SIZE_LIMIT_BYTES)" ]; then \
	    echo "❌ FAIL: $$bin exceeds $(SIZE_LIMIT_BYTES) bytes (.bss + .data = $$total)"; \
	    echo "   Reduce static buffers or refactor to stack/heap before merging."; \
	    exit 1; \
	  fi; \
	done
	@echo "✅ All binaries within 50 KB static RAM budget."
