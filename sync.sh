#!/bin/bash
#
# sync.sh — copia las personalizaciones desde la maquina hacia este repo.
#
# El repo es un espejo manual de ~/.config (y de unos pocos ficheros mas).
# Este script hace la parte aburrida: copiar lo que haya cambiado, avisar de
# lo sospechoso, enseñar el diff y commitear.
#
#   ./sync.sh                 copiar, mostrar diff, preguntar, commitear
#   ./sync.sh --dry-run       solo enseña qué cambiaría
#   ./sync.sh --yes           commitea sin preguntar
#   ./sync.sh --push          ademas hace push a origin
#   ./sync.sh -m "mensaje"    mensaje de commit
#   ./sync.sh --no-add        no mete ficheros nuevos, solo actualiza los seguidos
#   ./sync.sh --watch RUTA    añade un sitio donde buscar ficheros nuevos
#
# Mapeo repo <-> maquina:
#   config/...      -> ~/.config/...
#   dotfiles/.X     -> ~/.X
#   local-bin/x     -> ~/.local/bin/x
#
# Los ficheros nuevos solo se buscan en las rutas de --watch (por defecto
# ~/.config/omarchy, ~/.config/hypr y ~/.local/bin), para no arrastrar de
# golpe el arbol entero de ~/.config/nvim o cualquier cache.

set -uo pipefail

REPO=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
cd "$REPO" || exit 1

DRY=0 ASK=1 DO_ADD=1 DO_PUSH=0 MSG=""
WATCH=(
  "$HOME/.config/omarchy"
  "$HOME/.config/hypr"
  "$HOME/.local/bin"
)

while (( $# )); do
  case "$1" in
    --dry-run|-n) DRY=1; shift ;;
    --yes|-y) ASK=0; shift ;;
    --push) DO_PUSH=1; shift ;;
    --no-add) DO_ADD=0; shift ;;
    -m|--message) MSG=${2:-}; shift 2 ;;
    --watch) WATCH+=("${2:-}"); shift 2 ;;
    -h|--help) sed -n '2,26p' "${BASH_SOURCE[0]}"; exit 0 ;;
    *) echo "opcion desconocida: $1" >&2; exit 2 ;;
  esac
done

# --- exclusiones -------------------------------------------------------------
EXCLUDES=(.git node_modules __pycache__ '*.log' '*.sock' '*.pid' '*.tmp'
          '*.swp' '.DS_Store' Thumbs.db state cache themes backups lazy)
# Nombres que huelen a secreto: no se añaden sin --add-secrets.
SECRET_NAMES=('*token*' '*secret*' '*password*' '*passwd*' '*credentials*'
              '*.env' '.netrc' 'id_rsa*' 'id_ed2551*' '*.pem' '*.key' 'cookies*')

# Contenido que no debe acabar en GitHub ni aunque se llame inocentemente.
SECRET_BODY='ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|-----BEGIN [A-Z ]*PRIVATE KEY|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}'

MAXBYTES=$((1024 * 1024))

excluded() {
  local path=$1 base part
  base=${path##*/}
  case "$base" in
    *.log|*.sock|*.pid|*.tmp|*.swp|*.sample|.DS_Store|Thumbs.db) return 0 ;;
  esac
  for part in ${path//\// }; do
    case "$part" in
      .git|node_modules|__pycache__|state|cache|lazy|themes|backups|backgrounds) return 0 ;;
    esac
  done
  return 1
}

# Shims de mise: scripts generados que llaman a `mise use`/`exec mise`. No son
# personalizaciones, son basura de maquina.
mise_shim() {
  local f=$1
  [[ -f $f ]] || return 1
  head -5 "$f" 2>/dev/null | LC_ALL=C grep -qE 'MISE_|mise use|exec +"?[^"]*mise( |$)'
}

binary_file() {
  local f=$1
  [[ -f $f ]] || return 1
  [[ $(LC_ALL=C file --mime-encoding --brief "$f" 2>/dev/null) == binary ]]
}

secret_named() {
  local base=$1 pat
  for pat in "${SECRET_NAMES[@]}"; do
    case "$base" in $pat) return 0 ;; esac
  done
  return 1
}

secret_content() {
  local f=$1
  [[ -f $f ]] || return 1
  LC_ALL=C grep -qE "$SECRET_BODY" "$f" 2>/dev/null
}

# --- mapeos ------------------------------------------------------------------
live_of() {
  case $1 in
    config/*)     printf '%s' "$HOME/.config/${1#config/}" ;;
    dotfiles/*)
      local n=${1#dotfiles/}
      if [[ $n == .* ]]; then printf '%s' "$HOME/$n"
      else printf '%s' "$HOME/.$n"; fi ;;
    local-bin/*)  printf '%s' "$HOME/.local/bin/${1#local-bin/}" ;;
    *)            printf '' ;;
  esac
}

repo_of() {
  case $1 in
    "$HOME"/.config/*)     printf 'config/%s' "${1#$HOME/.config/}" ;;
    "$HOME"/.local/bin/*)  printf 'local-bin/%s' "${1#$HOME/.local/bin/}" ;;
    *)                     printf '' ;;
  esac
}

# --- paso 1: actualizar lo ya seguido ----------------------------------------
UPDATED=() SKIPPED_SYMLINK=() MISSING=() SECRETS=()

while IFS= read -r tracked; do
  live=$(live_of "$tracked")
  [[ -z $live ]] && continue
  if [[ -L $tracked ]]; then
    SKIPPED_SYMLINK+=("$tracked")
    continue
  fi
  if [[ ! -e $live ]]; then
    MISSING+=("$tracked")
    continue
  fi
  if cmp -s "$tracked" "$live"; then
    continue
  fi
  if secret_named "$(basename "$live")" || secret_content "$live"; then
    SECRETS+=("$tracked <- $live")
    continue
  fi
  if (( ! DRY )); then
    mkdir -p "$(dirname "$tracked")"
    cp -L -- "$live" "$tracked" || { echo "no se pudo copiar $live" >&2; continue; }
  fi
  UPDATED+=("$tracked")
done < <(git ls-files)

# --- paso 2: ficheros nuevos en las rutas vigiladas --------------------------
KNOWN_BASES=$(git ls-files | while IFS= read -r t; do basename "$t"; done | sort -u)
ADDED=()
while IFS= read -r live; do
  [[ -f $live ]] || continue          # ni symlinks ni cosas raras
  rp=$(repo_of "$live")
  [[ -z $rp ]] && continue
  excluded "$rp" && continue
  git ls-files --error-unmatch "$rp" >/dev/null 2>&1 && continue
  base=$(basename "$live")
  # ya guardado en otra ruta del repo (p.ej. omactheme/bin/omarchy-dock)
  grep -Fxq "$base" <<<"$KNOWN_BASES" && continue
  secret_named "$base" && { SECRETS+=("nuevo: $live"); continue; }
  mise_shim "$live" && continue
  if (( $(stat -c%s "$live") > MAXBYTES )); then echo "  salto $live (>1 MiB)"; continue; fi
  binary_file "$live" && { echo "  salto $live (binario, añadelo a mano)"; continue; }
  secret_content "$live" && { SECRETS+=("nuevo: $live"); continue; }
  if (( DO_ADD )); then
    if (( DRY )); then
      ADDED+=("$rp")
    else
      mkdir -p "$(dirname "$rp")"
      cp -L -- "$live" "$rp" && ADDED+=("$rp")
    fi
  fi
done < <(
  for root in "${WATCH[@]}"; do
    [[ -d $root ]] && find "$root" \( -type f -o -type l \) 2>/dev/null
  done
)

# --- informe -----------------------------------------------------------------
echo "espejo: $REPO"
echo "actualizados : ${#UPDATED[@]}"
for f in ${UPDATED[@]+"${UPDATED[@]}"}; do echo "  ~ $f"; done
echo "nuevos       : ${#ADDED[@]}"
for f in ${ADDED[@]+"${ADDED[@]}"}; do echo "  + $f"; done
(( ${#SKIPPED_SYMLINK[@]} )) && echo "symlinks del repo, no se tocan: ${SKIPPED_SYMLINK[*]}"
(( ${#MISSING[@]} )) && { echo "en el repo pero no en la maquina (se quedan como estan):"; printf '  ? %s\n' "${MISSING[@]}"; }
(( ${#SECRETS[@]} )) && { echo "NO añadidos, parecen secretos:"; printf '  ! %s\n' "${SECRETS[@]}"; }

if (( DRY )); then
  echo
  echo "dry-run: no se ha copiado nada"
  exit 0
fi

git add -A
if git diff --cached --quiet; then
  echo
  echo "ya estaba al dia: nada que commitear"
  exit 0
fi

echo
echo "--- cambios ---"
git diff --cached --stat | tail -25

if (( ASK )); then
  echo
  read -r -p "¿commitear? [s/N] " reply
  [[ $reply =~ ^[sSyY] ]] || { echo "sin commitear (los ficheros ya estan copiados)"; exit 0; }
fi

if [[ -z $MSG ]]; then
  MSG="Sincronizar personalizaciones ($(date +%Y-%m-%d))"
  MSG+=$'\n\n'
  MSG+="Actualizados: ${#UPDATED[@]}, nuevos: ${#ADDED[@]}."
  (( ${#UPDATED[@]} )) && MSG+=$'\n'"  ${UPDATED[*]}"
  (( ${#ADDED[@]} )) && MSG+=$'\n'"  + ${ADDED[*]}"
fi

git commit -q -F - <<<"$MSG" || { echo "fallo el commit" >&2; exit 1; }
echo "commiteado: $(git log --oneline -1)"

if (( DO_PUSH )); then
  git push origin HEAD || { echo "fallo el push" >&2; exit 1; }
  echo "enviado a origin"
else
  echo "pendiente de push: git push origin main"
fi
