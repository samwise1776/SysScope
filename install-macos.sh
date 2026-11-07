#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")"

if ! command -v brew >/dev/null 2>&1; then
  echo "Homebrew is required."
  echo "Install it from https://brew.sh"
  exit 1
fi

brew install gtk4 gtksourceview5 pkg-config

if ! ruby -e "require 'gtk4'; require 'cairo'" 2>/dev/null; then
  gem install gtk4 cairo
fi

if ! ruby -e "require 'gtksourceview5'" 2>/dev/null; then
  gem install gtksourceview5 || {
    echo "GtkSourceView Ruby binding unavailable."
    echo "The IDE can run without optional highlighting."
  }
fi

INSTALL_DIR="$HOME/Applications/SysScope"

mkdir -p "$INSTALL_DIR"
cp main.rb "$INSTALL_DIR/"

for item in sysscope.svg icon.png; do
  if [ -f "$item" ]; then
    cp "$item" "$INSTALL_DIR/"
  fi
done

for folder in sysscope_assets extensions; do
  if [ -d "$folder" ]; then
    cp -R "$folder" "$INSTALL_DIR/"
  fi
done

cat > "$INSTALL_DIR/run.sh" <<'RUN'
#!/bin/bash
cd "$(dirname "$0")"
exec ruby main.rb
RUN

chmod +x "$INSTALL_DIR/run.sh"

echo
echo "SysScope installed on macOS."
echo "Launch with: $INSTALL_DIR/run.sh"
