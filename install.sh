#!/bin/bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$HOME/.local/bin" "$HOME/.local/share/ralph"
install -m 755 "$ROOT_DIR/ralph.sh" "$HOME/.local/share/ralph/ralph.sh"

cat > "$HOME/.local/bin/ralph" <<'EOF'
#!/bin/bash
set -euo pipefail

if git_root="$(git -C "${PWD}" rev-parse --show-toplevel 2>/dev/null)"; then
  ROOT="$git_root"
else
  ROOT="$PWD"
fi

RALPH_ROOT_DIR="$ROOT" exec "$HOME/.local/share/ralph/ralph.sh" "$@"
EOF

chmod +x "$HOME/.local/bin/ralph"

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$HOME/.local/bin"; then
  if ! grep -Fq 'export PATH="$HOME/.local/bin:$PATH"' "$HOME/.zshrc" 2>/dev/null; then
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$HOME/.zshrc"
  fi
  echo "Added ~/.local/bin to PATH in ~/.zshrc. Restart your shell or run: source ~/.zshrc"
fi

echo "Installed ralph to ~/.local/bin/ralph"
