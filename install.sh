#!/bin/bash
# Restaura las personalizaciones de amartinomarchy en una máquina Omarchy.
# Uso: ./install.sh   (desde un terminal normal, con sudo/fingerprint disponible)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP="$HOME/.local/state/amartinomarchy/backups/$STAMP"

command -v omarchy >/dev/null || { echo "ERROR: esto es para Omarchy (falta el comando 'omarchy')"; exit 1; }

echo "==> Backup de la config actual en $BACKUP"
mkdir -p "$BACKUP"
for src in "$HOME/.config/hypr" "$HOME/.config/omarchy" "$HOME/.local/bin" \
           "$HOME/.bashrc" "$HOME/.XCompose"; do
  if [[ -e "$src" ]]; then
    rel="${src#$HOME/}"
    mkdir -p "$BACKUP/$(dirname "$rel")"
    cp -a "$src" "$BACKUP/$rel"
  fi
done
printf '%s\n' "$BACKUP" > "$HOME/.local/state/amartinomarchy/latest-backup"

echo "==> Copiando config/ a ~/.config/"
mkdir -p "$HOME/.config"
cp -a "$ROOT/config/." "$HOME/.config/"

echo "==> Copiando dotfiles/ a $HOME/"
cp -a "$ROOT/dotfiles/." "$HOME/"

echo "==> Instalando local-bin/ en ~/.local/bin/"
mkdir -p "$HOME/.local/bin"
cp -a "$ROOT/local-bin/." "$HOME/.local/bin/"
chmod +x "$HOME/.local/bin/"* 2>/dev/null || true

echo "==> Instalando paquetes AUR (packages/aur.txt)"
if command -v yay >/dev/null; then
  yay -S --needed --noconfirm - < "$ROOT/packages/aur.txt" || \
    echo "WARN: algunos paquetes AUR no se instalaron; revisa packages/aur.txt"
else
  echo "WARN: falta 'yay'; salta los paquetes AUR (pacman -S yay primero)"
fi

echo "==> Clonando temas externos"
mkdir -p "$HOME/.config/omarchy/themes"
while read -r name url commit; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  dest="$HOME/.config/omarchy/themes/$name"
  if [[ -d "$dest/.git" ]]; then
    git -C "$dest" fetch origin
  else
    rm -rf "$dest"
    git clone --quiet "$url" "$dest"
  fi
  git -C "$dest" checkout --quiet "$commit"
  echo "    $name -> $commit"
done < "$ROOT/themes.txt"

echo "==> Instalando omactheme (tahoe-dark, dock, tahoe-window, omarchy-dock)"
"$ROOT/omactheme/install.sh"

echo "==> Activando mission control (hymission + gestos)"
"$ROOT/omactheme/enable-mission-control.sh" || \
  echo "WARN: mission control no se activó (¿sin touchpad?); se puede reintentar después"

echo "==> Activando voxtype.service (user)"
systemctl --user enable --now voxtype.service 2>/dev/null || true

echo "==> Reiniciando shell y Hyprland"
omarchy restart shell 2>/dev/null || true
hyprctl reload 2>/dev/null || true

echo
echo "Listo. Backup anterior: $BACKUP"