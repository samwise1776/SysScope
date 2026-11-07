#!/usr/bin/env bash
set -euo pipefail

APP_ID="com.sysscope.app"
APP_NAME="SysScope"

PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="$HOME/.local/share/sysscope"
BIN_DIR="$HOME/.local/bin"
APPS_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
DESKTOP_DIR="$(xdg-user-dir DESKTOP 2>/dev/null || true)"

[ -n "$DESKTOP_DIR" ] || DESKTOP_DIR="$HOME/Desktop"

if [ ! -f "$PROJECT/main.rb" ]; then
    echo "ERROR: main.rb not found!"
    exit 1
fi

if [ ! -f "$PROJECT/icon.png" ]; then
    echo "ERROR: icon.png not found!"
    exit 1
fi

echo "Installing SysScope..."

mkdir -p "$INSTALL_DIR" "$BIN_DIR" "$APPS_DIR" "$ICON_DIR"

# Install application files
cp "$PROJECT/main.rb" "$INSTALL_DIR/"
cp "$PROJECT/icon.png" "$INSTALL_DIR/"

if [ -f "$PROJECT/sysscope.svg" ]; then
    cp "$PROJECT/sysscope.svg" "$INSTALL_DIR/"
fi

# Install launcher command
cat > "$BIN_DIR/sysscope" <<EOF
#!/usr/bin/env bash
cd "$INSTALL_DIR" || exit 1
exec ruby main.rb "\$@"
EOF

chmod +x "$BIN_DIR/sysscope"

# Install application icon
cp "$PROJECT/icon.png" "$ICON_DIR/$APP_ID.png"

# Create application launcher
cat > "$APPS_DIR/$APP_ID.desktop" <<EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=$APP_NAME
GenericName=System Monitor
Comment=Monitor CPU, RAM and running applications
Exec=$BIN_DIR/sysscope
Icon=$APP_ID
Terminal=false
Categories=System;Monitor;
StartupNotify=true
StartupWMClass=$APP_ID
EOF

chmod 644 "$APPS_DIR/$APP_ID.desktop"

# Create desktop shortcut
if [ -d "$DESKTOP_DIR" ]; then
    cp "$APPS_DIR/$APP_ID.desktop" "$DESKTOP_DIR/$APP_ID.desktop"
    chmod +x "$DESKTOP_DIR/$APP_ID.desktop"
    echo "Desktop shortcut installed."
else
    echo "Desktop folder not found; application menu launcher installed."
fi

# Refresh desktop application database
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APPS_DIR" || true
fi

echo
echo "================================="
echo " SysScope installed successfully!"
echo "================================="
echo "Application: $INSTALL_DIR"
echo "Icon:        $ICON_DIR/$APP_ID.png"
echo "Launcher:    $APPS_DIR/$APP_ID.desktop"
echo
echo "Open SysScope from your application menu."
echo "Or run: $BIN_DIR/sysscope"
