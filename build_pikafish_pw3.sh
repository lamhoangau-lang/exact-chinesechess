#!/usr/bin/env bash
#
# Cross-build Pikafish for Kindle Paperwhite 3 (and other kindlepw2 devices:
# PW2 / Voyage / KT2) so the engine actually runs on the old 3.0.35 kernel.
#
# Why this instead of the repo's build_pikafish.sh:
#   The stock script builds Pikafish in the Debian Bullseye container (glibc
#   2.31, min kernel 3.2) -> "kernel too old" on the PW3, exactly like the app
#   was. Here we use the koxtoolchain "kindlepw2" toolchain (the same one
#   KOReader uses: modern GCC + glibc 2.12, min kernel ~2.6.x) and link the
#   engine fully STATIC, so it is self-contained, needs no bundled libraries,
#   and ignores the app's LD_LIBRARY_PATH. ARCH=armv7 (softfp) matches the
#   toolchain and the device.
#
# Output: bin/armhf/pikafish  and  bin/armhf/pikafish.nnue

set -euo pipefail

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
PIKAFISH_SRC="${EXACT_CHINESECHESS_PIKAFISH_SRC:-$ROOT/Pikafish}"
OUT_DIR="$ROOT/bin/armhf"
ARCH="armv7"
JOBS="${JOBS:-2}"
TC_TAG="2025.05"
TC_URL="https://github.com/koreader/koxtoolchain/releases/download/${TC_TAG}/kindlepw2.tar.gz"
NNUE_URL="https://github.com/official-pikafish/Networks/releases/download/master-net/pikafish.nnue"

# ── 1. Cross toolchain ────────────────────────────────────────────────────
if ! command -v arm-kindlepw2-linux-gnueabi-g++ >/dev/null 2>&1; then
    echo "Downloading kindlepw2 toolchain ($TC_TAG) ..."
    curl -L --fail --progress-bar "$TC_URL" -o /tmp/kindlepw2.tar.gz
    tar -xf /tmp/kindlepw2.tar.gz -C "$HOME"
fi
GXX="$(command -v arm-kindlepw2-linux-gnueabi-g++ || true)"
if [ -z "$GXX" ]; then
    GXX="$(find "$HOME" -type f -name 'arm-kindlepw2-linux-gnueabi-g++' 2>/dev/null | head -n 1)"
fi
[ -n "$GXX" ] || { echo "ERROR: cross g++ not found after extraction." >&2; exit 1; }
export PATH="$(dirname "$GXX"):$PATH"
CXX="arm-kindlepw2-linux-gnueabi-g++"
CC="arm-kindlepw2-linux-gnueabi-gcc"
echo "Using cross compiler: $($CXX --version | head -n 1)"

[ -d "$PIKAFISH_SRC/src" ] || {
    echo "ERROR: Pikafish source not found at $PIKAFISH_SRC/src" >&2
    echo "Check out the repo with submodules (submodules: recursive)." >&2
    exit 1
}

# ── 2. ARM32 source patches (idempotent) ───────────────────────────────────
echo "Applying ARM32 patches ..."
python3 - "$PIKAFISH_SRC" <<'PYEOF'
import sys, pathlib
build = pathlib.Path(sys.argv[1])

types_h = build / "src" / "types.h"
src = types_h.read_text()
uint128_block = r'''
// Software 128-bit unsigned integer for ARM32 (no native __uint128_t).
#ifndef __SIZEOF_INT128__
struct uint128_soft {
    uint64_t hi, lo;
    constexpr uint128_soft() noexcept : hi(0), lo(0) {}
    constexpr uint128_soft(uint64_t v) noexcept : hi(0), lo(v) {}
    constexpr uint128_soft(uint64_t h, uint64_t l) noexcept : hi(h), lo(l) {}
    constexpr operator bool()                        const noexcept { return hi | lo; }
    explicit constexpr operator unsigned()           const noexcept { return (unsigned)lo; }
    explicit constexpr operator unsigned long()      const noexcept { return (unsigned long)lo; }
    explicit constexpr operator unsigned long long() const noexcept { return (unsigned long long)lo; }
    friend constexpr uint128_soft operator~(uint128_soft a) noexcept { return {~a.hi, ~a.lo}; }
    friend constexpr uint128_soft operator&(uint128_soft a, uint128_soft b) noexcept { return {a.hi & b.hi, a.lo & b.lo}; }
    friend constexpr uint128_soft operator|(uint128_soft a, uint128_soft b) noexcept { return {a.hi | b.hi, a.lo | b.lo}; }
    friend constexpr uint128_soft operator^(uint128_soft a, uint128_soft b) noexcept { return {a.hi ^ b.hi, a.lo ^ b.lo}; }
    constexpr uint128_soft& operator&=(uint128_soft b) noexcept { hi &= b.hi; lo &= b.lo; return *this; }
    constexpr uint128_soft& operator|=(uint128_soft b) noexcept { hi |= b.hi; lo |= b.lo; return *this; }
    constexpr uint128_soft& operator^=(uint128_soft b) noexcept { hi ^= b.hi; lo ^= b.lo; return *this; }
    friend constexpr uint128_soft operator<<(uint128_soft a, int n) noexcept {
        if (n == 0)   return a;
        if (n >= 128) return {};
        if (n >= 64)  return {a.lo << (n - 64), 0};
        return {(a.hi << n) | (a.lo >> (64 - n)), a.lo << n};
    }
    friend constexpr uint128_soft operator>>(uint128_soft a, int n) noexcept {
        if (n == 0)   return a;
        if (n >= 128) return {};
        if (n >= 64)  return {0, a.hi >> (n - 64)};
        return {a.hi >> n, (a.lo >> n) | (a.hi << (64 - n))};
    }
    constexpr uint128_soft& operator<<=(int n) noexcept { return *this = *this << n; }
    constexpr uint128_soft& operator>>=(int n) noexcept { return *this = *this >> n; }
    friend constexpr uint128_soft operator<<(uint128_soft a, unsigned int n) noexcept { return a << (int)n; }
    friend constexpr uint128_soft operator>>(uint128_soft a, unsigned int n) noexcept { return a >> (int)n; }
    friend constexpr uint128_soft operator+(uint128_soft a, uint128_soft b) noexcept {
        uint64_t new_lo = a.lo + b.lo;
        return {a.hi + b.hi + (new_lo < a.lo ? 1u : 0u), new_lo};
    }
    friend constexpr uint128_soft operator-(uint128_soft a, uint128_soft b) noexcept {
        return {a.hi - b.hi - (a.lo < b.lo ? 1u : 0u), a.lo - b.lo};
    }
    friend constexpr uint128_soft operator-(uint128_soft a, int b) noexcept { return a - uint128_soft((uint64_t)b); }
    friend constexpr uint128_soft operator-(uint128_soft a, unsigned int b) noexcept { return a - uint128_soft((uint64_t)b); }
    friend constexpr uint128_soft operator-(int a, uint128_soft b) noexcept { return uint128_soft((uint64_t)a) - b; }
    friend constexpr uint128_soft operator-(uint128_soft a) noexcept {
        uint64_t new_lo = ~a.lo + 1;
        return {~a.hi + (new_lo == 0 ? 1u : 0u), new_lo};
    }
    friend constexpr uint128_soft operator*(uint128_soft a, uint128_soft b) noexcept {
        const uint64_t a0 = a.lo & 0xFFFFFFFFu, a1 = a.lo >> 32;
        const uint64_t b0 = b.lo & 0xFFFFFFFFu, b1 = b.lo >> 32;
        const uint64_t p00 = a0 * b0, p01 = a0 * b1, p10 = a1 * b0, p11 = a1 * b1;
        const uint64_t mid = (p00 >> 32) + (p01 & 0xFFFFFFFFu) + (p10 & 0xFFFFFFFFu);
        return {p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32) + a.hi * b.lo + a.lo * b.hi,
                (p00 & 0xFFFFFFFFu) | ((mid & 0xFFFFFFFFu) << 32)};
    }
    friend constexpr bool operator==(uint128_soft a, uint128_soft b) noexcept { return a.lo == b.lo && a.hi == b.hi; }
    friend constexpr bool operator!=(uint128_soft a, uint128_soft b) noexcept { return !(a == b); }
    friend constexpr bool operator< (uint128_soft a, uint128_soft b) noexcept {
        return a.hi < b.hi || (a.hi == b.hi && a.lo < b.lo);
    }
};
#endif

'''
if "uint128_soft" not in src:
    src = src.replace("namespace Stockfish {", uint128_block + "namespace Stockfish {", 1)
    print("  types.h: inserted uint128_soft")
else:
    print("  types.h: uint128_soft already present")
old_bb = "using Bitboard = __uint128_t;"
new_bb = ("#ifdef __SIZEOF_INT128__\n"
          "using Bitboard = __uint128_t;\n"
          "#else\n"
          "using Bitboard = uint128_soft;\n"
          "#endif")
if old_bb in src:
    src = src.replace(old_bb, new_bb, 1)
    print("  types.h: conditionalized Bitboard typedef")
types_h.write_text(src)

bitboard_h = build / "src" / "bitboard.h"
src = bitboard_h.read_text()
old_lsb = ("    if (uint64_t(b))\n"
           "        return Square(__builtin_ctzll(b));\n"
           "    return Square(__builtin_ctzll(b >> 64) + 64);")
new_lsb = ("    if (uint64_t(b))\n"
           "        return Square(__builtin_ctzll(uint64_t(b)));\n"
           "    return Square(__builtin_ctzll(uint64_t(b >> 64)) + 64);")
if old_lsb in src:
    src = src.replace(old_lsb, new_lsb, 1)
    print("  bitboard.h: patched lsb()")
elif "uint64_t(b >> 64)" in src:
    print("  bitboard.h: lsb() already patched")
else:
    print("  bitboard.h: WARNING - lsb() pattern not found", file=sys.stderr)
bitboard_h.write_text(src)
print("Patches applied.")
PYEOF

# ── 2b. Force vfpv3 (no NEON) ───────────────────────────────────────────────
# Pikafish's armv7 preset forces -mfpu=neon, which lets GCC emit NEON loads
# that fault (SIGSEGV) in the NNUE path on the PW3's i.MX6 SoloLite. vfpv3 is
# exactly the FPU KOReader targets for kindlepw2, so it is known-good here.
echo "Forcing -mfpu=vfpv3 (dropping NEON) ..."
sed -i 's/-mfpu=neon/-mfpu=vfpv3/g' "$PIKAFISH_SRC/src/Makefile"

# ── 3. Build (static) ───────────────────────────────────────────────────────
mkdir -p "$OUT_DIR"
echo "Building Pikafish ARCH=$ARCH (static) with kindlepw2 ..."
make -C "$PIKAFISH_SRC/src" clean 2>/dev/null || true
# -static makes the engine self-contained, but glibc 2.12's static libpthread
# is only pulled in on demand and its thread/TLS setup then crashes (SIGSEGV)
# when the engine spawns its thread pool at startup. --whole-archive forces
# the complete libpthread into the binary, which fixes the crash.
make -C "$PIKAFISH_SRC/src" -j"$JOBS" build \
    ARCH="$ARCH" COMP=gcc CXX="$CXX" CC="$CC" \
    EXTRALDFLAGS="-static -Wl,--whole-archive -lpthread -Wl,--no-whole-archive"

[ -f "$PIKAFISH_SRC/src/pikafish" ] || { echo "ERROR: pikafish binary not produced." >&2; exit 1; }
cp "$PIKAFISH_SRC/src/pikafish" "$OUT_DIR/pikafish"
chmod 755 "$OUT_DIR/pikafish"

# ── 4. NNUE network ─────────────────────────────────────────────────────────
if [ -f "$PIKAFISH_SRC/src/pikafish.nnue" ]; then
    cp "$PIKAFISH_SRC/src/pikafish.nnue" "$OUT_DIR/pikafish.nnue"
else
    echo "Fetching default NNUE ..."
    curl -L --fail --progress-bar "$NNUE_URL" -o "$OUT_DIR/pikafish.nnue"
fi

echo ""
echo "=== Pikafish result ==="
file "$OUT_DIR/pikafish"
du -h "$OUT_DIR/pikafish" "$OUT_DIR/pikafish.nnue"
echo "(must say 'statically linked' and 'for GNU/Linux 2.6.x')"
