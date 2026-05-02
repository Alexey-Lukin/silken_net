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

.PHONY: all queen soldier bio_contract tinyml encryption seed_derivation clean

all: queen soldier bio_contract tinyml encryption seed_derivation

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

$(BINDIR)/test_queen: test_queen_logic.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_queen_logic.c

$(BINDIR)/test_soldier: test_soldier_logic.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_soldier_logic.c

$(BINDIR)/test_bio_contract: test_bio_contract.c
	$(CC) $(CFLAGS) -o $@ test_bio_contract.c -lm

$(BINDIR)/test_tinyml: test_tinyml_pipeline.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_tinyml_pipeline.c -lm

$(BINDIR)/test_encryption: test_encryption.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_encryption.c

# [SEC.11] Host parity for SilkenNet::SeedDerivation. Uses OpenSSL
# libcrypto on host; firmware MCU side runs the same primitives via
# mbedTLS (already linked for AES). Same standard primitives →
# byte-identical (x0, y0, z0) for the same (K_seed, epoch_day) tuple.
$(BINDIR)/test_seed_derivation: test_seed_derivation.c
	$(CC) $(CFLAGS) -o $@ test_seed_derivation.c -lcrypto -lm

clean:
	rm -f $(BINDIR)/test_queen $(BINDIR)/test_soldier $(BINDIR)/test_bio_contract \
	      $(BINDIR)/test_tinyml $(BINDIR)/test_encryption $(BINDIR)/test_seed_derivation
