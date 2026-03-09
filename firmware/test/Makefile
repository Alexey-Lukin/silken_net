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

.PHONY: all queen soldier clean

all: queen soldier

queen: $(BINDIR)/test_queen
	@./$(BINDIR)/test_queen

soldier: $(BINDIR)/test_soldier
	@./$(BINDIR)/test_soldier

$(BINDIR)/test_queen: test_queen_logic.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_queen_logic.c

$(BINDIR)/test_soldier: test_soldier_logic.c hal_mock.h
	$(CC) $(CFLAGS) -o $@ test_soldier_logic.c

clean:
	rm -f $(BINDIR)/test_queen $(BINDIR)/test_soldier
