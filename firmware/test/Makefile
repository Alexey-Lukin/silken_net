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

.PHONY: all queen soldier bio_contract tinyml logmel encryption seed_derivation ccm selftest sym_selftest at_engine uart_ring flash_kv flash_ring flash_ota attest key_ratchet fauna coverage size-check clean

all: queen soldier bio_contract tinyml logmel encryption seed_derivation ccm selftest sym_selftest at_engine uart_ring flash_kv flash_ring flash_ota attest key_ratchet fauna

queen: $(BINDIR)/test_queen
	@./$(BINDIR)/test_queen

soldier: $(BINDIR)/test_soldier
	@./$(BINDIR)/test_soldier

bio_contract: $(BINDIR)/test_bio_contract
	@./$(BINDIR)/test_bio_contract

tinyml: $(BINDIR)/test_tinyml
	@./$(BINDIR)/test_tinyml

logmel: $(BINDIR)/test_logmel
	@./$(BINDIR)/test_logmel

encryption: $(BINDIR)/test_encryption
	@./$(BINDIR)/test_encryption

seed_derivation: $(BINDIR)/test_seed_derivation
	@./$(BINDIR)/test_seed_derivation

ccm: $(BINDIR)/test_ccm
	@./$(BINDIR)/test_ccm

selftest: $(BINDIR)/test_ccm_selftest
	@./$(BINDIR)/test_ccm_selftest

sym_selftest: $(BINDIR)/test_sym_selftest
	@./$(BINDIR)/test_sym_selftest

at_engine: $(BINDIR)/test_at_engine
	@./$(BINDIR)/test_at_engine

uart_ring: $(BINDIR)/test_uart_rx_ring
	@./$(BINDIR)/test_uart_rx_ring

flash_kv: $(BINDIR)/test_flash_kv
	@./$(BINDIR)/test_flash_kv

flash_ring: $(BINDIR)/test_flash_ring
	@./$(BINDIR)/test_flash_ring

flash_ota: $(BINDIR)/test_flash_ota
	@./$(BINDIR)/test_flash_ota

attest: $(BINDIR)/test_queen_attest
	@./$(BINDIR)/test_queen_attest

fauna: $(BINDIR)/test_fauna_session
	@./$(BINDIR)/test_fauna_session

key_ratchet: $(BINDIR)/test_key_ratchet
	@./$(BINDIR)/test_key_ratchet

$(BINDIR)/test_queen: test_queen_logic.c hal_mock.h ../common/silken_crc.h
	$(CC) $(CFLAGS) -o $@ test_queen_logic.c

$(BINDIR)/test_soldier: test_soldier_logic.c hal_mock.h ../common/lorenz_seed.h ../common/silken_sha256.h ../common/silken_crc.h ../common/adc_convert.h ../common/wall_time.h
	$(CC) $(CFLAGS) -o $@ test_soldier_logic.c

$(BINDIR)/test_bio_contract: test_bio_contract.c
	$(CC) $(CFLAGS) -o $@ test_bio_contract.c -lm

$(BINDIR)/test_tinyml: test_tinyml_pipeline.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_tinyml_pipeline.c -lm

# [FW.25] Compute_LogMel parity vs silken_ml golden vectors (docs/03_03 §3.4).
# Generated tables come from `python -m silken_ml.codegen.emit_c` (committed).
$(BINDIR)/test_logmel: test_logmel.c ../common/logmel.c ../common/logmel.h \
                       ../common/logmel_contract.h ../common/logmel_hann_table.h \
                       ../common/logmel_mel_bank.h ../common/logmel_golden_vectors.h
	$(CC) $(CFLAGS) -I../common -o $@ test_logmel.c ../common/logmel.c -lm

$(BINDIR)/test_encryption: test_encryption.c hal_mock.h ../queen/coap_iv.h
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_encryption.c $(OPENSSL_LIBS)

# [FW.3/FW.56] AT-токенайзер + CoAP PDU + SIM7070G розмова — pure, без OpenSSL.
$(BINDIR)/test_at_engine: test_at_engine.c ../queen/at_engine.h ../queen/coap_pdu.h ../queen/sim7070_coap.h
	$(CC) $(CFLAGS) -o $@ test_at_engine.c

# [FW.3] Кільце-вид поверх circular-DMA RX — гонки знімка/IRQ, overrun, wrap.
$(BINDIR)/test_uart_rx_ring: test_uart_rx_ring.c ../queen/uart_rx_ring.h ../queen/at_engine.h
	$(CC) $(CFLAGS) -o $@ test_uart_rx_ring.c

# [ARCH.28/FW.54] Flash-KV журнал — RAM-мок + power-cut fault-injection.
$(BINDIR)/test_flash_kv: test_flash_kv.c ../common/flash_kv.c ../common/flash_kv.h ../common/silken_crc.h
	$(CC) $(CFLAGS) -I../common -o $@ test_flash_kv.c ../common/flash_kv.c

# [ARCH.35] W25Q32 sector-ring — NOR-мок (program 1→0) + power-cut fault-injection.
$(BINDIR)/test_flash_ring: test_flash_ring.c ../common/flash_ring.c ../common/flash_ring.h
	$(CC) $(CFLAGS) -I../common -o $@ test_flash_ring.c ../common/flash_ring.c

# [ARCH.40] Монолітна fauna-сесія — Welford + named-тест «жодного STOP2 посеред сесії».
$(BINDIR)/test_fauna_session: test_fauna_session.c ../common/fauna_session.h ../common/logmel_contract.h
	$(CC) $(CFLAGS) -I../common -o $@ test_fauna_session.c -lm

# [FW.52-г] OTA contract blob writer — RAM-мок + magic-LAST power-cut safety.
$(BINDIR)/test_flash_ota: test_flash_ota.c ../common/flash_ota.c ../common/flash_ota.h ../common/flash_kv.h
	$(CC) $(CFLAGS) -I../common -o $@ test_flash_ota.c ../common/flash_ota.c

# [L1 QATT] Queen-attestation конверт — Monocypher (pinned submodule) ↔ OpenSSL
# parity + end-to-end збірка/розбір; golden-KAT дзеркалиться у RSpec.
MONOCYPHER_SRC = ../extern/monocypher/src
$(BINDIR)/test_queen_attest: test_queen_attest.c ../common/queen_attest.h \
                             $(MONOCYPHER_SRC)/monocypher.c \
                             $(MONOCYPHER_SRC)/optional/monocypher-ed25519.c
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -I$(MONOCYPHER_SRC) -I$(MONOCYPHER_SRC)/optional \
	  -o $@ test_queen_attest.c \
	  $(MONOCYPHER_SRC)/monocypher.c $(MONOCYPHER_SRC)/optional/monocypher-ed25519.c \
	  $(OPENSSL_LIBS)

# [FW.17] Hash-Ratchet ротація LoRa-ключа — pure-C KAT (parity з RSpec).
$(BINDIR)/test_key_ratchet: test_key_ratchet.c ../common/key_ratchet.h ../common/silken_sha256.h ../common/silken_crc.h
	$(CC) $(CFLAGS) -o $@ test_key_ratchet.c

# [SEC.11] Host parity for SilkenNet::SeedDerivation. Uses OpenSSL
# libcrypto on host; firmware MCU side runs the same primitives via
# pure-C silken_sha256.h (FW.30; no mbedTLS). Same standard primitives →
# byte-identical (x0, y0, z0) for the same (K_seed, epoch_day) tuple.
$(BINDIR)/test_seed_derivation: test_seed_derivation.c ../common/lorenz_seed.h ../common/silken_sha256.h
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_seed_derivation.c $(OPENSSL_LIBS) -lm

# [FW.2] AES-128-CCM packet roundtrip — links libcrypto for the mock HAL.
$(BINDIR)/test_ccm: test_ccm.c hal_mock.h ../common/lora_ccm.h ../common/ccm_kat_vectors.h
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_ccm.c $(OPENSSL_LIBS)

# [FW.2] On-target CCM self-test (POST) — host verification via OpenSSL mock.
$(BINDIR)/test_ccm_selftest: test_ccm_selftest.c hal_mock.h ../common/lora_ccm.h ../common/ccm_selftest.h ../common/ccm_kat_vectors.h
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_ccm_selftest.c $(OPENSSL_LIBS)

# [ARCH.42] On-target ECB/CBC self-test (ARCH.42 transitional paths) —
# host verification via OpenSSL mock (HAL_MOCK_SYM_ENABLED).
$(BINDIR)/test_sym_selftest: test_sym_selftest.c hal_mock.h ../common/sym_selftest.h ../common/sym_kat_vectors.h
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_sym_selftest.c $(OPENSSL_LIBS)

clean:
	rm -f $(BINDIR)/test_queen $(BINDIR)/test_soldier $(BINDIR)/test_bio_contract \
	      $(BINDIR)/test_tinyml $(BINDIR)/test_logmel $(BINDIR)/test_encryption \
	      $(BINDIR)/test_seed_derivation $(BINDIR)/test_ccm $(BINDIR)/test_ccm_selftest \
	      $(BINDIR)/test_sym_selftest $(BINDIR)/test_queen_attest \
	      $(BINDIR)/test_at_engine $(BINDIR)/test_uart_rx_ring \
	      $(BINDIR)/test_flash_kv $(BINDIR)/test_flash_ring $(BINDIR)/test_flash_ota \
	      $(BINDIR)/test_key_ratchet $(BINDIR)/test_fauna_session \
	      *.gcno *.gcda *.gcov coverage_raw.txt

# [FW.26] CI gate — Static RAM budget check (.bss + .data ≤ 50 KB).
#
# STM32WLE5JC має 64 KB SRAM. Виміряний леджер (2026-06-11) — One-Home у
# 03_03 §6 + firmware/scripts/check_ram_budget.sh (хедер): mruby-куча 38 392 Б
# (FW.55, не «~4 KB»-міф) + stack 12 288 + статика ~8 000 ⇒ стеля tensor
# arena 7-15 КБ. АВТОРИТЕТНИЙ гейт статики — CI `[FW.26] ARM static-RAM`
# (--hal-objects, реальні .obj обох main.c); цей host-гейт лишається швидким
# локальним проксі проти тихої регресії СТАТИКИ (нові buffers, EMA-вікна,
# OTA масиви) — його поріг свідомо грубий.
#
# Використовуємо host `size` проти host-тест build як ПЛАЦХОЛЬДЕР, доки
# lab build з arm-none-eabi-size не активний. Host build містить ті ж
# глобальні буфери (raw_audio_buffer, audio_buffer, OTA chunk map etc.),
# що і firmware build, тому регресія тут = регресія на target.
#
# Threshold 51200 bytes = 50 KB (ділимо 64 KB SRAM на буфери і кошти
# виконання, залишаючи runtime ~14 KB запасу). Перевищення → exit 1.
SIZE_LIMIT_BYTES ?= 51200
# [TEST.1] Coverage-lane host-тестів — ВИДИМІСТЬ дір, не гейт.
# Інструментована перебудова (--coverage, -O0 щоб інлайн не з'їдав рядки) +
# прогін усієї сюїти + gcov-звіт по owned-модулях (../common, ../queen,
# ../soldier — і .c, і header-only через атрибуцію в TU, що їх включає;
# для header'а з кількох TU береться найкращий показник). Свідомо ПОЗА
# звітом: test_*.c самі по собі, hal_mock, ../extern (чужий код). Межі
# host-лейну чесні (04_06 §B.1.1): test_soldier/queen_logic міряють
# ДЗЕРКАЛО логіки main.c, не сам main.c — його покриває bench/QEMU-фаза.
# GCOV: gcc-gcov на CI (Linux), на macOS /usr/bin/gcov = llvm-cov шим.
GCOV ?= gcov

coverage:
	@$(MAKE) clean >/dev/null
	@echo "[TEST.1] Інструментована збірка + прогін host-сюїти (--coverage -O0)…"
	@$(MAKE) all CFLAGS="-Wall -Wextra -Wpedantic -std=c11 -I. -O0 --coverage" >/dev/null
	@rm -f coverage_raw.txt
	@for g in *.gcda; do $(GCOV) "$$g" >> coverage_raw.txt 2>/dev/null || true; done
	@echo ""
	@echo "[TEST.1] Покриття owned-модулів (рядки):"
	@echo "─────────────────────────────────────────────────────────────"
	@awk "/^File '/ { f=\$$0; sub(/^File '/,\"\",f); sub(/'\$$/,\"\",f) } \
	     /^Lines executed:/ && f ~ /\.\.\/(common|queen|soldier)\// { \
	       split(\$$0,a,\":\"); split(a[2],b,\"% of \"); \
	       if (!(f in pct) || b[1]+0 > pct[f]) { pct[f]=b[1]+0; n[f]=b[2]+0 } f=\"\" } \
	     END { for (x in pct) printf \"  %6.2f%%  %5d рядків  %s\n\", pct[x], n[x], x }" \
	     coverage_raw.txt | sort -k4
	@echo "─────────────────────────────────────────────────────────────"
	@echo "Анотовані *.gcov поряд (рядок-у-рядок); прибрати: make clean."

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
