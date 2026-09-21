#!/bin/sh
# Downloads the JOGL and GlueGen 2.3.2 native libraries for linux-armv6hf
# (Raspberry Pi) from Maven Central into a directory (default: lib/), under the
# names the TheMap launcher expects, and verifies their SHA-256.
#
# These are a runtime-only dependency of JOGL's native library loader, so
# build.sh doesn't need them - only a machine that actually runs the app does.
set -e

DEST=${1:-lib}
BASE=https://repo1.maven.org/maven2/org/jogamp

sha256() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# fetch <maven path> <local name> <expected sha256>
fetch() {
  out="$DEST/$2"
  if [ -f "$out" ] && [ "$(sha256 "$out")" = "$3" ]; then
    echo "have $2"
    return
  fi
  curl -fsSL "$BASE/$1" -o "$out"
  if [ "$(sha256 "$out")" != "$3" ]; then
    echo "checksum mismatch for $2" >&2
    rm -f "$out"
    exit 1
  fi
  echo "fetched $2"
}

mkdir -p "$DEST"
fetch jogl/jogl-all/2.3.2/jogl-all-2.3.2-natives-linux-armv6hf.jar \
  jogl-all-natives-linux-armv6hf.jar \
  f55b619145b9ce809acb488e61d378ab8fbcbd96104d99548cb758c3fddb6172
fetch gluegen/gluegen-rt/2.3.2/gluegen-rt-2.3.2-natives-linux-armv6hf.jar \
  gluegen-rt-natives-linux-armv6hf.jar \
  12b95c5d3b303c003dc2088de4a91111ba2aeef7dd8bbba00112ee3c48e5c867
