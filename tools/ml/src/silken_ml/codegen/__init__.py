"""C code generation — emit the committed ``firmware/common/logmel_*.h`` tables.

The single source for the Hann window, the HTK mel filter bank (sparse triplet),
and the golden I/O vectors that the firmware host-test asserts against. All three
headers are generated from the pure-stdlib oracle, so they need no heavy deps and
regenerate identically on any machine (drift-checked by ``emit_c --check``).
"""
