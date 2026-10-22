#!/bin/sh
# Rebuild the SDL2 bundled in soh.app with sdl2-iokit-composite-gamepad.patch so
# composite Bluetooth gamepads (e.g. GameSir G7 Pro) are detected on macOS.
# Usage: patch-sdl-composite-gamepad.sh [/path/to/soh.app]
# The original library is kept next to it as libSDL2-2.0.0.dylib.original.

set -e

APP="${1:-/Applications/soh.app}"
SDL_VERSION="2.32.10"
SDL_SHA256="5f5993c530f084535c65a6879e9b26ad441169b3e25d789d83287040a9ca5165"
PATCH="$(cd "$(dirname "$0")" && pwd)/sdl2-iokit-composite-gamepad.patch"
FRAMEWORKS="$APP/Contents/Frameworks"
LIB="libSDL2-2.0.0.dylib"

if [ ! -f "$FRAMEWORKS/$LIB" ]; then
    echo "No $LIB in $FRAMEWORKS" >&2
    exit 1
fi

BUNDLED_VERSION="$(otool -L "$FRAMEWORKS/$LIB" | sed -n 2p | sed -E 's/.*current version ([0-9.]+).*/\1/')"
if [ "$BUNDLED_VERSION" != "3201.10.0" ]; then
    echo "soh.app bundles SDL current version $BUNDLED_VERSION, this script targets $SDL_VERSION (3201.10.0)." >&2
    echo "Update SDL_VERSION/SDL_SHA256 and check the patch still applies." >&2
    exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
cd "$WORK"

curl -sL -o SDL2.tar.gz "https://github.com/libsdl-org/SDL/releases/download/release-$SDL_VERSION/SDL2-$SDL_VERSION.tar.gz"
echo "$SDL_SHA256  SDL2.tar.gz" | shasum -a 256 -c -
tar xzf SDL2.tar.gz
patch -d "SDL2-$SDL_VERSION" -p1 < "$PATCH"

for ARCH in arm64 x86_64; do
    mkdir "build-$ARCH"
    (
        cd "build-$ARCH"
        HOST="$ARCH"
        [ "$ARCH" = "arm64" ] && HOST="aarch64"
        CC="clang -arch $ARCH" CFLAGS="-O2 -mmacosx-version-min=10.15" \
            "../SDL2-$SDL_VERSION/configure" --host="$HOST-apple-darwin" --disable-static > configure.log
        make -j"$(sysctl -n hw.ncpu)" > make.log
    )
done

lipo -create build-arm64/build/.libs/$LIB build-x86_64/build/.libs/$LIB -output "$LIB"
install_name_tool -id "@executable_path/../Frameworks/$LIB" "$LIB" 2> /dev/null
codesign --force -s - "$LIB"

if [ ! -f "$FRAMEWORKS/$LIB.original" ]; then
    cp -p "$FRAMEWORKS/$LIB" "$FRAMEWORKS/$LIB.original"
fi
# Rename into place so a running soh keeps its mapped copy instead of crashing
cp "$LIB" "$FRAMEWORKS/.$LIB.new"
mv -f "$FRAMEWORKS/.$LIB.new" "$FRAMEWORKS/$LIB"

echo "Installed patched $LIB into $FRAMEWORKS. Quit soh (Cmd+Q) and open it again."
