#!/bin/zsh
# Build kartei-core (Anki's backend + bridge) for macOS, iOS and Android, then
# refresh what the apps consume: the XCFramework, the Android .so and the
# generated Swift/Kotlin/Java message code. Run from anywhere.
set -e
export PATH="$HOME/.rustup/toolchains/1.99.0-aarch64-apple-darwin/bin:$PATH"
cd "$(dirname "$0")"
# C code and Rust must agree on the minimum OS version, or the device link fails.
export IPHONEOS_DEPLOYMENT_TARGET=17.0 MACOSX_DEPLOYMENT_TARGET=14.0
NDK="${ANDROID_NDK_HOME:-$HOME/Library/Android/sdk/ndk/29.0.14206865}/toolchains/llvm/prebuilt/darwin-x86_64/bin"
quiet() { grep -E "^error|-->|Finished" || true; }

for T in aarch64-apple-darwin aarch64-apple-ios-sim aarch64-apple-ios; do
  echo "== $T"; cargo build --release --lib --target $T 2>&1 | quiet
done
echo "== aarch64-linux-android"
CC_aarch64_linux_android="$NDK/aarch64-linux-android26-clang" \
CXX_aarch64_linux_android="$NDK/aarch64-linux-android26-clang++" \
AR_aarch64_linux_android="$NDK/llvm-ar" \
CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$NDK/aarch64-linux-android26-clang" \
cargo build --release --lib --target aarch64-linux-android 2>&1 | quiet

echo "== XCFramework"
mkdir -p ../build/headers && cp include/kartei_core.h ../build/headers/
printf 'module KarteiCore {\n    header "kartei_core.h"\n    export *\n}\n' > ../build/headers/module.modulemap
rm -rf ../build/KarteiCore.xcframework
args=()
for T in aarch64-apple-darwin aarch64-apple-ios-sim aarch64-apple-ios; do
  args+=(-library target/$T/release/libkartei_core.a -headers ../build/headers)
done
xcodebuild -create-xcframework $args -output ../build/KarteiCore.xcframework | tail -1

echo "== Android library"
mkdir -p ../../apps/android/app/src/main/jniLibs/arm64-v8a
"$NDK/llvm-strip" -o ../../apps/android/app/src/main/jniLibs/arm64-v8a/libkartei_core.so target/aarch64-linux-android/release/libkartei_core.so

echo "== Generated code"
mkdir -p ../gen/swift ../gen/kotlin ../gen/java
cargo run --release --example gen_index -- target/aarch64-apple-darwin/release/build/anki_descriptors.bin ../gen/swift/BackendMethods.swift ../gen/kotlin/BackendMethods.kt 2>&1 | quiet
(cd ../../spike/anki/proto && protoc --swift_out=../../../core/gen/swift --java_out=lite:../../../core/gen/java -I . anki/*.proto 2>/dev/null)
echo done
