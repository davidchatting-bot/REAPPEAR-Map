#!/bin/sh
# Builds TheMap.jar from source/*.pde: combines the tabs into build/TheMap.java,
# compiles it, and packages the classes. Needs core.jar and Ani.jar in $LIB
# (default: lib/). JOGL and GlueGen aren't needed to compile, only to run.
set -e
cd "$(dirname "$0")"

LIB=${LIB:-lib}
OUT=${OUT:-$LIB/TheMap.jar}

python3 tools/pde2java.py source build/TheMap.java

rm -rf build_classes
mkdir -p build_classes
javac -cp "$LIB/core.jar:$LIB/Ani.jar" \
  -d build_classes build/TheMap.java
jar --create --file="$OUT" --main-class=TheMap -C build_classes .

echo "built $OUT"
