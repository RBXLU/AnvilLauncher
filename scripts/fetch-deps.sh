#!/usr/bin/env bash
# Собирает всё, чего нет в исходниках: Java-рантаймы под iOS, LWJGL, рендереры и GLFW-шим.
# Запускать на macOS с Xcode и JDK 17+:  ./scripts/fetch-deps.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEPS="$ROOT/deps"
BUNDLED="$ROOT/App/Resources/Bundled"
FRAMEWORKS="$DEPS/Frameworks"
# Готовые iOS-сборки OpenJDK, LWJGL, gl4es, ANGLE и MobileGlues берём у проекта Amethyst (GPL-3.0).
AMETHYST_REPO="https://github.com/AngelAuraMC/Amethyst-iOS.git"
AMETHYST_COMMIT="f98c4133c72d39e06ceac42b57cc4477c52105fc"
JRE_URL="https://assets.angelauramc.dev/openjdk/ios-arm64"
JAVA_VERSIONS="${JAVA_VERSIONS:-8 17 21 25}"

mkdir -p "$DEPS" "$BUNDLED/runtimes" "$BUNDLED/lwjgl" "$FRAMEWORKS"

echo "==> Java-рантаймы: $JAVA_VERSIONS"
for v in $JAVA_VERSIONS; do
  dest="$BUNDLED/runtimes/java-$v"
  [ -f "$dest/release" ] && continue
  tmp="$(mktemp -d)"
  curl -fSL "$JRE_URL/jre$v-ios-aarch64.zip" -o "$tmp/jre.zip"
  unzip -q "$tmp/jre.zip" -d "$tmp"
  mkdir -p "$dest"
  tar xf "$tmp"/jre*.tar.xz -C "$dest"
  rm -rf "$tmp" "$dest"/{bin,include,legal,man,jmods,lib/src.zip,lib/ct.sym}
done

echo "==> Исходники Amethyst ($AMETHYST_COMMIT)"
SRC="$DEPS/amethyst"
if [ ! -d "$SRC/.git" ]; then
  git init -q "$SRC"
  git -C "$SRC" remote add origin "$AMETHYST_REPO"
fi
git -C "$SRC" fetch -q --depth 1 origin "$AMETHYST_COMMIT"
git -C "$SRC" checkout -q FETCH_HEAD
git -C "$SRC" submodule update -q --init --depth 1 Natives/external/MobileGlues
# perfetto нужен только для профилирования и весит гигабайты — его не тянем.
git -C "$SRC/Natives/external/MobileGlues" submodule update -q --init --depth 1 \
  src/main/cpp/include/FastSTL src/main/cpp/3rdparty/glm src/main/cpp/3rdparty/xxhash

echo "==> LWJGL и нативные библиотеки"
cp "$SRC"/JavaApp/libs/lwjgl/*.jar "$BUNDLED/lwjgl/"
NATIVE="$SRC/Natives/resources/Frameworks"
cp -R "$NATIVE"/liblwjgl*.dylib "$NATIVE"/libopenal.dylib "$NATIVE"/libgl4es_114.dylib \
      "$NATIVE"/libEGL.framework "$NATIVE"/libGLESv2.framework "$FRAMEWORKS/"

echo "==> MobileGlues (OpenGL 4.x поверх ANGLE/Metal)"
if [ "$(uname -s)" = "Darwin" ]; then
  MG="$SRC/Natives/external/MobileGlues/src/main/cpp"
  if cmake -S "$MG" -B "$DEPS/build-mobileglues" -DMACOS=1 \
        -DCMAKE_SYSTEM_NAME=Darwin -DCMAKE_SYSTEM_PROCESSOR=aarch64 -DCMAKE_CROSSCOMPILING=true \
        -DCMAKE_OSX_SYSROOT="$(xcrun --sdk iphoneos --show-sdk-path)" \
        -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET=14.0 >/dev/null \
     && cmake --build "$DEPS/build-mobileglues" --config RelWithDebInfo -j"$(sysctl -n hw.ncpu)" --target mobileglues; then
    cp "$DEPS/build-mobileglues/libmobileglues.dylib" "$MG/libraries/ios/libspirv-cross-c-shared.0.dylib" "$FRAMEWORKS/"
  else
    echo "warning: MobileGlues не собрался, останется только gl4es (версии до 1.16.5)"
  fi
else
  echo "warning: MobileGlues собирается только на macOS, пропускаю"
fi

echo "==> JNI-заголовки"
JDK_HOME="${JAVA_HOME:-$(/usr/libexec/java_home 2>/dev/null || dirname "$(dirname "$(readlink -f "$(command -v javac)")")")}"
mkdir -p "$DEPS/jni"
cp "$JDK_HOME"/include/jni.h "$DEPS/jni/"
cp "$JDK_HOME"/include/*/jni_md.h "$DEPS/jni/"

echo "==> GLFW-шим (anvil-glfw.jar)"
OUT="$(mktemp -d)"
javac --release 8 -nowarn -d "$OUT" \
  -cp "$BUNDLED/lwjgl/lwjgl.jar:$BUNDLED/lwjgl/lwjgl-glfw.jar" \
  $(find "$ROOT/Java/src" -name '*.java')
jar cf "$BUNDLED/anvil-glfw.jar" -C "$OUT" .
rm -rf "$OUT"

echo "Готово."
