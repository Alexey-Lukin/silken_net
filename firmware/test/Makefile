# SPDX-License-Identifier: AGPL-3.0-or-later
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

# [build_standard_variables] Honour env/CLI compiler+linker vars (`?=`/`+=`), never
# replace them: a packager/distro can pass e.g.
#   CFLAGS="-g -fstack-protector-strong -D_FORTIFY_SOURCE=2 -Wl,-z,relro" CC=clang
# and the project EXTENDS with its mandatory flags (-std=c11 -I.) on top. These are
# single-invocation gcc compile+link recipes, so CFLAGS-borne linker flags (-Wl,…)
# reach the linker too. Makes ASAN / distro-hardening easy to turn on (OpenSSF silver).
CC      ?= gcc
CFLAGS  += -Wall -Wextra -Wpedantic -std=c11 -I. -O2
BINDIR   = .

# [FW.2] OpenSSL flags via pkg-config (portable across macOS/Homebrew + Linux).
# Used by tests that link libcrypto for AES-CCM mock or HKDF: test_encryption,
# test_seed_derivation. Empty fallback if pkg-config absent.
OPENSSL_CFLAGS = $(shell pkg-config --cflags openssl 2>/dev/null)
OPENSSL_LIBS   = $(shell pkg-config --libs openssl 2>/dev/null || echo -lcrypto)

.PHONY: all queen soldier bio_contract tinyml logmel audio_model encryption seed_derivation ccm selftest sym_selftest rx_route at_engine uart_ring flash_kv flash_ring flash_ota attest key_ratchet cmd_queue fauna bme280 tdma helium soft_timer helium_mac_smoke cad coverage size-check asan clean

all: queen soldier bio_contract tinyml logmel audio_model encryption seed_derivation ccm selftest sym_selftest rx_route at_engine uart_ring flash_kv flash_ring flash_ota attest key_ratchet cmd_queue fauna bme280 tdma helium soft_timer helium_mac_smoke cad

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

# [FW.4] Generated INT8 acoustic model — Run_Inference vs silken_ml golden vectors.
audio_model: $(BINDIR)/test_audio_model
	@./$(BINDIR)/test_audio_model

$(BINDIR)/test_audio_model: test_audio_model.c ../soldier/silken_net_audio_model.h silken_net_audio_model_golden.h
	$(CC) $(CFLAGS) -o $@ test_audio_model.c -lm

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

# [FW.2] Queen RX-маршрутизація + 29B CoAP-запис — pure байти, без OpenSSL.
rx_route: $(BINDIR)/test_queen_rx_route
	@./$(BINDIR)/test_queen_rx_route

# [ARCH.34] Helium SOS pure-половина: wire-парність з HeliumSosWorker + тригер.
helium: $(BINDIR)/test_helium_sos
	@./$(BINDIR)/test_helium_sos

# [ARCH.34] owned таймер-движок + systime під vendored LoRaMac-node.
soft_timer: $(BINDIR)/test_soft_timer
	@./$(BINDIR)/test_soft_timer

# [ARCH.34] host-smoke СПРАВЖНЬОГО LoRaMac-node на стаб-радіо: adapter-епізод
# TX'ить криптографічно валідний JoinRequest (MHDR/23B/DevNonce-монотонність).
helium_mac_smoke: $(BINDIR)/test_helium_mac_smoke
	@./$(BINDIR)/test_helium_mac_smoke

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

bme280: $(BINDIR)/test_bme280
	@./$(BINDIR)/test_bme280

key_ratchet: $(BINDIR)/test_key_ratchet
	@./$(BINDIR)/test_key_ratchet

cmd_queue: $(BINDIR)/test_soldier_cmd_queue
	@./$(BINDIR)/test_soldier_cmd_queue

tdma: $(BINDIR)/test_tdma_schedule
	@./$(BINDIR)/test_tdma_schedule

cad: $(BINDIR)/test_cad_sniff
	@./$(BINDIR)/test_cad_sniff

$(BINDIR)/test_queen: test_queen_logic.c hal_mock.h ../common/silken_crc.h
	$(CC) $(CFLAGS) -o $@ test_queen_logic.c

$(BINDIR)/test_soldier: test_soldier_logic.c hal_mock.h ../common/lorenz_seed.h ../common/silken_sha256.h ../common/silken_crc.h ../common/adc_convert.h ../common/wall_time.h ../common/beacon_dedup.h ../common/tx_defer.h ../common/acoustic_ledger.h
	$(CC) $(CFLAGS) -o $@ test_soldier_logic.c

$(BINDIR)/test_tdma_schedule: test_tdma_schedule.c ../common/tdma_schedule.h
	$(CC) $(CFLAGS) -o $@ test_tdma_schedule.c

# [ARCH.26 L3] CAD-нюх Провідника + PANIC extended-preamble — pure, без HAL.
$(BINDIR)/test_cad_sniff: test_cad_sniff.c ../common/cad_sniff.h ../common/wall_time.h
	$(CC) $(CFLAGS) -o $@ test_cad_sniff.c

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
$(BINDIR)/test_at_engine: test_at_engine.c ../queen/at_engine.h ../queen/coap_pdu.h ../queen/sim7070_coap.h ../queen/sim7070_udp.h
	$(CC) $(CFLAGS) -o $@ test_at_engine.c

# [FW.3] Кільце-вид поверх circular-DMA RX — гонки знімка/IRQ, overrun, wrap.
$(BINDIR)/test_uart_rx_ring: test_uart_rx_ring.c ../queen/uart_rx_ring.h ../queen/at_engine.h
	$(CC) $(CFLAGS) -o $@ test_uart_rx_ring.c

# [ARCH.28/FW.54] Flash-KV журнал — RAM-мок + power-cut fault-injection.
# (+ FW.8 Z-пороги та FW.2 FC high-water — споживацькі секції поверх KV.)
$(BINDIR)/test_flash_kv: test_flash_kv.c ../common/flash_kv.c ../common/flash_kv.h ../common/silken_crc.h ../common/lorenz_thresholds.h ../common/fc_hiwater.h ../common/lora_ccm.h ../common/beacon_dedup.h
	$(CC) $(CFLAGS) -I../common -o $@ test_flash_kv.c ../common/flash_kv.c

# [ARCH.35] W25Q32 sector-ring — NOR-мок (program 1→0) + power-cut fault-injection.
$(BINDIR)/test_flash_ring: test_flash_ring.c ../common/flash_ring.c ../common/flash_ring.h
	$(CC) $(CFLAGS) -I../common -o $@ test_flash_ring.c ../common/flash_ring.c

# [ARCH.40] Монолітна fauna-сесія — Welford + named-тест «жодного STOP2 посеред сесії».
$(BINDIR)/test_fauna_session: test_fauna_session.c ../common/fauna_session.h ../common/logmel_contract.h
	$(CC) $(CFLAGS) -I../common -o $@ test_fauna_session.c -lm

# [HW.32] BME280 компенсація (int datasheet §8.2 ↔ float-референс §8.1) + VPD-confounder.
$(BINDIR)/test_bme280: test_bme280.c ../common/bme280.h
	$(CC) $(CFLAGS) -I../common -o $@ test_bme280.c -lm

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

# [FW.20-Q2] Черга Soldier-bound команд (0x9A/0x9E) — рефлекс-реле Королеви.
$(BINDIR)/test_soldier_cmd_queue: test_soldier_cmd_queue.c ../queen/soldier_cmd_queue.h ../common/key_ratchet.h ../common/silken_crc.h ../common/silken_sha256.h
	$(CC) $(CFLAGS) -o $@ test_soldier_cmd_queue.c

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

# [FW.2] Queen RX route + 29B-запис — pure (golden-звірка проти KAT-констант).
$(BINDIR)/test_queen_rx_route: test_queen_rx_route.c ../queen/rx_route.h ../common/lora_ccm.h ../common/ccm_kat_vectors.h
	$(CC) $(CFLAGS) -o $@ test_queen_rx_route.c

$(BINDIR)/test_helium_sos: test_helium_sos.c ../queen/helium_sos.h
	$(CC) $(CFLAGS) -o $@ test_helium_sos.c

$(BINDIR)/test_soft_timer: test_soft_timer.c ../queen/lorawan_glue/soft_timer.c ../queen/lorawan_glue/soft_timer.h ../queen/lorawan_glue/systime.c ../queen/lorawan_glue/systime.h
	$(CC) $(CFLAGS) -o $@ test_soft_timer.c ../queen/lorawan_glue/soft_timer.c ../queen/lorawan_glue/systime.c

# [ARCH.34] Vendored LoRaMac-node TU-и + owned glue (профіль lorawan_conf.h:
# EU868/ClassA/soft-se). Той самий список піде в ARM hal-lane (CMake).
LORAWAN_MW   = ../extern/stm32-mw-lorawan
LORAWAN_INC  = -I../queen/lorawan_glue -I../queen -I../common \
               -I$(LORAWAN_MW)/Mac -I$(LORAWAN_MW)/Mac/Region -I$(LORAWAN_MW)/Crypto \
               -I$(LORAWAN_MW)/LmHandler -I$(LORAWAN_MW)/LmHandler/Packages \
               -I$(LORAWAN_MW)/Utilities -I../extern/subghz-phy/radio_driver
LORAWAN_SRCS = $(LORAWAN_MW)/Mac/LoRaMac.c $(LORAWAN_MW)/Mac/LoRaMacAdr.c \
               $(LORAWAN_MW)/Mac/LoRaMacClassB.c $(LORAWAN_MW)/Mac/LoRaMacCommands.c \
               $(LORAWAN_MW)/Mac/LoRaMacConfirmQueue.c $(LORAWAN_MW)/Mac/LoRaMacCrypto.c \
               $(LORAWAN_MW)/Mac/LoRaMacParser.c $(LORAWAN_MW)/Mac/LoRaMacSerializer.c \
               $(LORAWAN_MW)/Mac/Region/Region.c $(LORAWAN_MW)/Mac/Region/RegionCommon.c \
               $(LORAWAN_MW)/Mac/Region/RegionEU868.c \
               $(LORAWAN_MW)/Crypto/soft-se.c $(LORAWAN_MW)/Crypto/cmac.c \
               $(LORAWAN_MW)/Crypto/lorawan_aes.c \
               $(LORAWAN_MW)/LmHandler/LmHandler.c $(LORAWAN_MW)/LmHandler/NvmDataMgmt.c \
               $(LORAWAN_MW)/LmHandler/Packages/LmhpCompliance.c \
               $(LORAWAN_MW)/LmHandler/Packages/LmhpPackagesRegistration.c \
               $(LORAWAN_MW)/Utilities/utilities.c \
               ../queen/lorawan_glue/soft_timer.c ../queen/lorawan_glue/systime.c \
               ../queen/lorawan_glue/lora_info.c ../queen/lorawan_glue/helium_mac.c \
               ../common/flash_kv.c

# -DAES_DEC_PREKEYED: лише для цього бінаря — мок-LNS ШИФРУЄ JoinAccept
# AES-decrypt-ом (девайс відновлює encrypt-ом), а девайсова половина стека
# decrypt-у не потребує ніде, тож vendored lorawan_aes.h тримає його #if 0.
# -lm: RegionCommon.c кличе floor() — під -O0 (coverage lane) компілятор НЕ
# інлайнить його як builtin (як на -O1/-O2), тож libm лінкується явно.
$(BINDIR)/test_helium_mac_smoke: test_helium_mac_smoke.c $(LORAWAN_SRCS) ../queen/helium_sos.h
	$(CC) $(CFLAGS) -Wno-unused-parameter -DAES_DEC_PREKEYED $(LORAWAN_INC) -o $@ test_helium_mac_smoke.c $(LORAWAN_SRCS) -lm

# [ARCH.42] On-target ECB/CBC self-test (ARCH.42 transitional paths) —
# host verification via OpenSSL mock (HAL_MOCK_SYM_ENABLED).
$(BINDIR)/test_sym_selftest: test_sym_selftest.c hal_mock.h ../common/sym_selftest.h ../common/sym_kat_vectors.h
	$(CC) $(CFLAGS) $(OPENSSL_CFLAGS) -o $@ test_sym_selftest.c $(OPENSSL_LIBS)

clean:
	rm -f $(BINDIR)/test_queen $(BINDIR)/test_soldier $(BINDIR)/test_bio_contract \
	      $(BINDIR)/test_tinyml $(BINDIR)/test_logmel $(BINDIR)/test_encryption \
	      $(BINDIR)/test_seed_derivation $(BINDIR)/test_ccm $(BINDIR)/test_ccm_selftest \
	      $(BINDIR)/test_sym_selftest $(BINDIR)/test_queen_attest \
	      $(BINDIR)/test_queen_rx_route $(BINDIR)/test_helium_sos \
	      $(BINDIR)/test_soft_timer $(BINDIR)/test_helium_mac_smoke \
	      $(BINDIR)/test_at_engine $(BINDIR)/test_uart_rx_ring \
	      $(BINDIR)/test_flash_kv $(BINDIR)/test_flash_ring $(BINDIR)/test_flash_ota \
	      $(BINDIR)/test_key_ratchet $(BINDIR)/test_soldier_cmd_queue \
	      $(BINDIR)/test_fauna_session \
	      $(BINDIR)/test_bme280 $(BINDIR)/test_audio_model \
	      $(BINDIR)/test_tdma_schedule $(BINDIR)/test_cad_sniff \
	      *.gcno *.gcda *.gcov coverage_raw.txt
	rm -rf $(BINDIR)/*.dSYM

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

# [TEST.5] Динамічна memory-safety смуга — ASan + UBSan re-instrumented rebuild.
# Закриває OpenSSF `dynamic_analysis_unsafe`: проєкт везе memory-unsafe C, тож
# статичного cppcheck (firmware_lint) + `-Wall` НЕ досить — ця смуга реально
# ВИКОНУЄ кожен host-тест під AddressSanitizer (heap/stack/global overflow,
# use-after-free/return, double-free) + UBSanitizer (signed-overflow, OOB-shift,
# misalign/null-deref). Той самий re-instrumented-rebuild ідіом, що й `coverage:`
# — оверрайд CFLAGS на рекурсивному $(MAKE) all (libcrypto/-I монокіфера
# дописуються per-target, тому sanitizer-CFLAGS компонуються чисто).
# detect_leaks=0 свідомо: OpenSSL one-time global init (test_encryption,
# test_queen_attest) ніколи не звільняється за дизайном (короткоживучі тести не
# кличуть OPENSSL_cleanup) → LSAN-«still reachable» = хибнопозитив, не buffer-баг;
# критерій цілить overwrites/UAF/UB, які ASan+UBSan покривають (Monocypher heap
# не алокує). macOS clang без LSAN → прапор no-op локально, дієвий на Linux CI.
ASAN_CFLAGS = -Wall -Wextra -Wpedantic -std=c11 -I. -O1 -g \
              -fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer

asan:
	@$(MAKE) clean >/dev/null
	@echo "[TEST.5] ASan+UBSan re-instrumented build + прогін усієї host-сюїти…"
	@ASAN_OPTIONS=halt_on_error=1:abort_on_error=1:detect_leaks=0 \
	 UBSAN_OPTIONS=halt_on_error=1:abort_on_error=1:print_stacktrace=1 \
	 $(MAKE) all CFLAGS="$(ASAN_CFLAGS)"
	@echo "✅ TEST.5: уся host-сюїта чиста під AddressSanitizer + UBSanitizer."
	@$(MAKE) clean >/dev/null   # ASAN shadow/redzone роздуває .bss/.data → прибрати за собою, інакше наступний size-check міряє інструментовані бінарники й рве 50KB-бюджет

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
