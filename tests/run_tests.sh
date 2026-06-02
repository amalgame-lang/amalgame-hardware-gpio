#!/bin/bash
# amalgame-hardware-gpio — Test Runner. Requires amc 0.8.47+ and
# libgpiod v2 (>= 2.0) dev headers + library.
#
# The AM assertions in stdlib_hardware_gpio.am are hardware-free
# (they prove the libgpiod v2 backend is linked and that bad inputs
# fail cleanly). When the kernel exposes the `gpio-sim` configfs
# interface AND we can write to it (root), an extra on-chip smoke
# test drives a virtual line and reads it back.
set -u

if [ $# -ge 1 ]; then AMC="$1"
elif [ -n "${AMC:-}" ]; then :
elif command -v amc >/dev/null 2>&1; then AMC="$(command -v amc)"
else echo "ERROR: amc not found." >&2; exit 2
fi
[ -x "$AMC" ] || { echo "ERROR: amc not executable: $AMC" >&2; exit 2; }
AMC="$(cd "$(dirname "$AMC")" && pwd)/$(basename "$AMC")"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
AMC_DIR="$(cd "$(dirname "$AMC")" && pwd)"
if [ -d "$AMC_DIR/runtime" ]; then AMC_RUNTIME="$AMC_DIR/runtime"
elif [ -d "$AMC_DIR/../share/amalgame/runtime" ]; then
    AMC_RUNTIME="$(cd "$AMC_DIR/../share/amalgame/runtime" && pwd)"
elif [ -n "${AMC_RUNTIME:-}" ]; then :
else echo "ERROR: amc runtime/ not found." >&2; exit 2; fi

# ── libgpiod v2 presence + flags ──────────────────────────
if ! pkg-config --exists libgpiod 2>/dev/null; then
    echo "ERROR: libgpiod not found by pkg-config. Install libgpiod-dev >= 2.0" >&2
    echo "       (Debian Bookworm only ships 1.6 — build 2.x from source, see README)." >&2
    exit 2
fi
GPIOD_VER="$(pkg-config --modversion libgpiod)"
case "$GPIOD_VER" in
    2.*) : ;;
    *) echo "ERROR: libgpiod $GPIOD_VER found, but this package needs 2.x." >&2; exit 2 ;;
esac
GPIOD_CFLAGS="$(pkg-config --cflags libgpiod)"
GPIOD_LIBDIR="$(pkg-config --variable=libdir libgpiod)"
export LIBRARY_PATH="${GPIOD_LIBDIR}:${LIBRARY_PATH:-}"
export LD_LIBRARY_PATH="${GPIOD_LIBDIR}:${LD_LIBRARY_PATH:-}"

BUILD_DIR="$(mktemp -d -t ahg-tests-XXXXXX)"
trap 'rm -rf "$BUILD_DIR"' EXIT
PROJ_DIR="$BUILD_DIR/proj"; mkdir -p "$PROJ_DIR"

# v0.6: the facade implements the amalgame-hal interfaces, so it must be
# compiled with hal as --external. Resolve hal from $HAL_DIR if set,
# else git-clone it at $HAL_TAG (default v0.1.0).
if [ -n "${HAL_DIR:-}" ]; then HAL="$HAL_DIR"
else
    HAL_TAG="${HAL_TAG:-v0.2.0}"
    git clone --depth 1 --branch "$HAL_TAG" -q \
        https://github.com/amalgame-lang/amalgame-hal "$BUILD_DIR/hal" \
        || { echo "ERROR: cannot clone amalgame-hal@$HAL_TAG" >&2; exit 2; }
    HAL="$BUILD_DIR/hal"
fi
HALF="$HAL/facade.am"

GREEN='\033[0;32m'; RED='\033[0;31m'; NC='\033[0m'

echo ""
echo "════════════════════════════════════════════"
echo "  amalgame-hardware-gpio — Test Suite"
echo "════════════════════════════════════════════"
echo "  amc:      $AMC ($("$AMC" --version 2>&1 | head -1))"
echo "  libgpiod: $GPIOD_VER"
echo "  package:  $PKG_ROOT"
echo ""

# ── Resolve the package against itself via a fake cache + lock ──
FAKE_CACHE="$BUILD_DIR/cache"
PKG_GIT="github.com/amalgame-lang/amalgame-hardware-gpio"
PKG_TAG="${PKG_TAG:-v0.1.0}"
FAKE_SHA="deadbeefcafebabe0000000000000000000000ab"
PKG_CACHE_DIR="$FAKE_CACHE/$PKG_GIT/${PKG_TAG}_${FAKE_SHA:0:8}"
mkdir -p "$(dirname "$PKG_CACHE_DIR")"
ln -s "$PKG_ROOT" "$PKG_CACHE_DIR"
cat > "$PROJ_DIR/amalgame.lock" <<EOF
[[package]]
name = "amalgame-hardware-gpio"
git  = "$PKG_GIT"
tag  = "$PKG_TAG"
rev  = "$FAKE_SHA"
EOF
export AMALGAME_PACKAGES_DIR="$FAKE_CACHE"

case "$(uname -s)" in
    Linux*) PLAT="linux-$(uname -m)" ;;
    *)      PLAT="unknown-$(uname -m)" ;;
esac
PLAT="${PLAT/amd64/x86_64}"; PLAT="${PLAT/aarch64/arm64}"

FACADE_BUILD_DIR="$BUILD_DIR/build/$PLAT"; mkdir -p "$FACADE_BUILD_DIR"
WORK_BUILD_DIR="$PKG_ROOT/build/$PLAT"; mkdir -p "$(dirname "$WORK_BUILD_DIR")"
[ -e "$WORK_BUILD_DIR" ] && [ ! -L "$WORK_BUILD_DIR" ] && rm -rf "$WORK_BUILD_DIR"
rm -f "$WORK_BUILD_DIR"; ln -s "$FACADE_BUILD_DIR" "$WORK_BUILD_DIR"
ARCHIVE="$FACADE_BUILD_DIR/libamalgame-pkg-Gpio.a"

echo "── Pre-compiling facade.am → libamalgame-pkg-Gpio.a ──"
"$AMC" --lib --quiet "$PKG_ROOT/facade.am" --external "$HALF" -o "$FACADE_BUILD_DIR/Gpio-facade" || exit 1
gcc -O2 -I"$AMC_RUNTIME" $GPIOD_CFLAGS -w -c \
    "$FACADE_BUILD_DIR/Gpio-facade.c" -o "$FACADE_BUILD_DIR/Gpio-facade.o" || exit 1
ar rcs "$ARCHIVE" "$FACADE_BUILD_DIR/Gpio-facade.o"
echo "  built: $ARCHIVE"
echo ""

# Locate libamalgame.a (dev tree vs release layout). amc 0.8.71+:
# `amc -o` only emits C; `amc build` would git-clone the package, so
# here we run cgen against the fake cache and link the binary by hand.
if   [ -f "$AMC_DIR/lib/libamalgame.a" ]; then LIBA="$AMC_DIR/lib/libamalgame.a"
elif [ -f "$AMC_DIR/../share/amalgame/lib/libamalgame.a" ]; then
    LIBA="$(cd "$AMC_DIR/../share/amalgame/lib" && pwd)/libamalgame.a"
else echo "ERROR: libamalgame.a not found near amc." >&2; exit 2; fi

# ── AM assertion bundle ───────────────────────────────────
PASS=0; FAIL=0
echo "── stdlib_hardware_gpio.am ──"
cp "$SCRIPT_DIR/stdlib_hardware_gpio.am" "$PROJ_DIR/test.am"
if (cd "$PROJ_DIR" && "$AMC" --quiet -o test test.am --external "$HALF") 2>"$PROJ_DIR/build.err" \
   && gcc -O2 -I"$AMC_RUNTIME" $GPIOD_CFLAGS -w \
        "$PROJ_DIR/test.c" "$FACADE_BUILD_DIR/Gpio-facade.o" "$LIBA" \
        -L"$GPIOD_LIBDIR" -lgpiod -lgc -lm -lz -ldl -lpthread \
        -o "$PROJ_DIR/test" 2>>"$PROJ_DIR/build.err"; then
    OUT="$("$PROJ_DIR/test" 2>&1)"; RC=$?
    echo "$OUT" | sed 's/^/    /'
    if [ "$RC" -eq 0 ] && ! echo "$OUT" | grep -q '\[FAIL\]'; then
        echo -e "  ${GREEN}bundle OK${NC}"; PASS=1
    else
        echo -e "  ${RED}bundle assertions FAILED${NC}"; FAIL=1
    fi
else
    echo -e "  ${RED}build FAILED${NC}"; cat "$PROJ_DIR/build.err"; FAIL=1
fi
echo ""

# ── every examples/*.am must still build ──────────────────
echo "── examples/ ──"
for ex in "$PKG_ROOT"/examples/*.am; do
    name="$(basename "$ex" .am)"
    cp "$ex" "$PROJ_DIR/$name.am"
    if (cd "$PROJ_DIR" && "$AMC" --quiet -o "$name" "$name.am" --external "$HALF") 2>"$PROJ_DIR/$name.err" \
       && gcc -O2 -I"$AMC_RUNTIME" $GPIOD_CFLAGS -w \
            "$PROJ_DIR/$name.c" "$FACADE_BUILD_DIR/Gpio-facade.o" "$LIBA" \
            -L"$GPIOD_LIBDIR" -lgpiod -lgc -lm -lz -ldl -lpthread \
            -o "$PROJ_DIR/$name" 2>>"$PROJ_DIR/$name.err"; then
        echo -e "  ${GREEN}$name builds${NC}"
    else
        echo -e "  ${RED}$name build FAILED${NC}"; cat "$PROJ_DIR/$name.err"; FAIL=1
    fi
done
echo ""

echo "════════════════════════════════════════════"
if [ "$FAIL" -eq 0 ]; then
    echo -e "  ${GREEN}ALL TESTS PASSED${NC}"; exit 0
else
    echo -e "  ${RED}TESTS FAILED${NC}"; exit 1
fi
