#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/ModuleCache build
export CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/ModuleCache"
swift build -c release --disable-sandbox --cache-path "$PWD/.build/cache" --scratch-path "$PWD/.build"
bin_dir=$(swift build -c release --show-bin-path --disable-sandbox --cache-path "$PWD/.build/cache" --scratch-path "$PWD/.build")
app="$PWD/build/Octo.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/DualPane" "$app/Contents/MacOS/DualPane"
cp Info.plist "$app/Contents/Info.plist"
cp Sources/DualPane/Resources/OctoDock.png "$app/Contents/Resources/OctoDock.png"
python3 make-icons.py
cp Assets/AppIcon.icns "$app/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$app"
printf '已构建：%s\n' "$app"
