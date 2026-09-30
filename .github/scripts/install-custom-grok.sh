#!/usr/bin/env bash
# Installs (or updates) the custom grok published by .github/workflows/custom-build.yml.
#
#   curl -fsSL https://raw.githubusercontent.com/soilderone/grok-build/custom/.github/scripts/install-custom-grok.sh | bash
#
# It replaces `grok` where the official installer put it (~/.grok/bin, else ~/.local/bin; override with GROK_INSTALL_DIR),
# keeps the official one as `grok.official`, and sets `[cli] auto_update = false` so the updater cannot swap the official build back in.
set -euo pipefail

repo="${GROK_CUSTOM_REPO:-soilderone/grok-build}"
tag="${GROK_CUSTOM_TAG:-custom-latest}"
grok_home="${GROK_HOME:-$HOME/.grok}"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) asset=grok-macos-arm64 ;;
  Linux-x86_64) asset=grok-linux-x86_64 ;;
  *)
    echo "error: no custom grok build for $(uname -s) $(uname -m)" >&2
    exit 1
    ;;
esac

if [ -n "${GROK_INSTALL_DIR:-}" ]; then
  dir="$GROK_INSTALL_DIR"
elif [ -d "$grok_home/bin" ]; then
  dir="$grok_home/bin"
else
  dir="$HOME/.local/bin"
fi
mkdir -p "$dir"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

url="https://github.com/$repo/releases/download/$tag/$asset.tar.gz"
echo "Downloading $url"
curl -fL --progress-bar -o "$tmp/grok.tar.gz" "$url"
curl -fsSL -o "$tmp/grok.tar.gz.sha256" "$url.sha256"

expected="$(cut -d' ' -f1 < "$tmp/grok.tar.gz.sha256")"
if command -v sha256sum >/dev/null 2>&1; then
  actual="$(sha256sum "$tmp/grok.tar.gz" | cut -d' ' -f1)"
else
  actual="$(shasum -a 256 "$tmp/grok.tar.gz" | cut -d' ' -f1)"
fi
if [ "$expected" != "$actual" ]; then
  echo "error: checksum mismatch for $asset.tar.gz" >&2
  exit 1
fi
tar -xzf "$tmp/grok.tar.gz" -C "$tmp"

# The official install is a symlink into ~/.grok/downloads; keep it reachable for rollback
if [ -L "$dir/grok" ] && [ ! -e "$dir/grok.official" ]; then
  ln -s "$(readlink "$dir/grok")" "$dir/grok.official"
fi
install -m 0755 "$tmp/grok" "$dir/grok.new"
mv -f "$dir/grok.new" "$dir/grok"

# Turn the auto-updater off: it would replace this build with the official release
config="$grok_home/config.toml"
mkdir -p "$grok_home"
touch "$config"
awk '
  /^[[:space:]]*\[/ {
    if (in_cli && !done) { print "auto_update = false"; done = 1 }
    in_cli = ($0 ~ /^[[:space:]]*\[cli\][[:space:]]*(#.*)?$/)
    if (in_cli) saw_cli = 1
    print
    next
  }
  in_cli && /^[[:space:]]*auto_update[[:space:]]*=/ {
    if (!done) { print "auto_update = false"; done = 1 }
    next
  }
  { print }
  END {
    if (in_cli && !done) print "auto_update = false"
    if (!saw_cli) { print ""; print "[cli]"; print "auto_update = false" }
  }
' "$config" > "$tmp/config.toml"
cp "$tmp/config.toml" "$config"

echo "Installed $("$dir/grok" --version) to $dir/grok (auto-update disabled in $config)"
if [ -e "$dir/grok.official" ]; then
  echo "Official build kept as $dir/grok.official; to roll back: mv -f \"$dir/grok.official\" \"$dir/grok\""
fi

resolved="$(command -v grok 2>/dev/null || true)"
if [ "$resolved" != "$dir/grok" ]; then
  echo
  echo "note: \`grok\` on your PATH resolves to '${resolved:-nothing}', not $dir/grok."
  echo "      Add this to your shell profile (~/.zshrc or ~/.bashrc), then open a new terminal:"
  echo "      export PATH=\"$dir:\$PATH\""
fi
