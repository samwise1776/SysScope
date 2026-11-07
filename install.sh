#!/usr/bin/env bash
set -euo pipefail

echo "Installing SysScope v1.0.2 for Linux..."

APP_DIR="$HOME/.local/share/sysscope"
BIN_DIR="$HOME/.local/bin"
DESKTOP_DIR="$HOME/.local/share/applications"

command -v ruby >/dev/null || {
  echo "Ruby is required."
  exit 1
}

mkdir -p "$APP_DIR" "$BIN_DIR" "$DESKTOP_DIR"

SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"

cp "$SOURCE_DIR/main.rb" "$APP_DIR/"

for file in sysscope_autoupdate.rb icon.png sysscope.svg; do
  if [ -f "$SOURCE_DIR/$file" ]; then
    cp "$SOURCE_DIR/$file" "$APP_DIR/"
  fi
done

for folder in sysscope_assets extensions; do
  if [ -d "$SOURCE_DIR/$folder" ]; then
    cp -R "$SOURCE_DIR/$folder" "$APP_DIR/"
  fi
done

cat > "$BIN_DIR/sysscope" <<'LAUNCH'
#!/usr/bin/env bash
cd "$HOME/.local/share/sysscope" || exit 1
exec ruby main.rb "$@"
LAUNCH

chmod +x "$BIN_DIR/sysscope"

cat > "$DESKTOP_DIR/sysscope.desktop" <<EOF
[Desktop Entry]
Name=SysScope
Comment=System Monitor and Development Environment
Exec=$BIN_DIR/sysscope %u
Icon=$APP_DIR/icon.png
Terminal=false
Type=Application
Categories=System;Development;
MimeType=x-scheme-handler/sysscope;
StartupNotify=true
EOF

xdg-mime default sysscope.desktop x-scheme-handler/sysscope 2>/dev/null || true
update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

echo "SysScope v1.0.2 installed!"
echo "Launch with: $BIN_DIR/sysscope"
