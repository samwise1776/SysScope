#!/usr/bin/env bash
set -euo pipefail

echo "Installing SysScope v1.0.2 for macOS..."

APP_DIR="$HOME/Applications/SysScope.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"

command -v ruby >/dev/null || {
  echo "Ruby is required."
  exit 1
}

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

mkdir -p "$MACOS" "$RESOURCES"

cp "$SOURCE_DIR/main.rb" "$RESOURCES/"

for file in sysscope_autoupdate.rb icon.png sysscope.svg; do
  if [ -f "$SOURCE_DIR/$file" ]; then
    cp "$SOURCE_DIR/$file" "$RESOURCES/"
  fi
done

for folder in sysscope_assets extensions; do
  if [ -d "$SOURCE_DIR/$folder" ]; then
    cp -R "$SOURCE_DIR/$folder" "$RESOURCES/"
  fi
done

cat > "$MACOS/SysScope" <<'LAUNCH'
#!/usr/bin/env bash
cd "$(dirname "$0")/../Resources" || exit 1
exec ruby main.rb "$@"
LAUNCH

chmod +x "$MACOS/SysScope"

cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
"http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>SysScope</string>
  <key>CFBundleDisplayName</key>
  <string>SysScope</string>
  <key>CFBundleIdentifier</key>
  <string>com.sysscope.app</string>
  <key>CFBundleExecutable</key>
  <string>SysScope</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>1.0.2</string>
  <key>CFBundleVersion</key>
  <string>102</string>
  <key>CFBundleURLTypes</key>
  <array>
    <dict>
      <key>CFBundleURLName</key>
      <string>SysScope URL</string>
      <key>CFBundleURLSchemes</key>
      <array>
        <string>sysscope</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

echo "SysScope v1.0.2 installed!"
echo "Open ~/Applications/SysScope.app"
