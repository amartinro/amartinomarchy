# amartinomarchy

Backup de las personalizaciones de mi sistema Omarchy (Arch + Hyprland).
Con esto se puede restaurar la configuración completa en otra máquina.

## Contenido

| Ruta | Origen | Descripción |
|------|--------|-------------|
| `config/hypr/` | `~/.config/hypr/` | Hyprland: bindings, monitors, input, looknfeel, mission-control, mouse, tahoe-overrides, hyprsunset |
| `config/omarchy/` | `~/.config/omarchy/` | Shell (bar, idle), dock, plugins, hooks, branding, default agent |
| `config/omarchy/plugins/amartin.mouse-mapper/` | — | App para mapear botones del Logitech MX Master 3 (overlay + `mxmouse-events.py`) |
| `config/omarchy/plugins/amartin.monitor/` | — | Widget de brillo/pantalla (clonado de `omarchy.monitor`) |
| `config/omarchy/plugins/dock/` | — | Dock estilo Tahoe con magnificación (también lo instala `omactheme`) |
| `config/omarchy/plugins/amartin.kairos/` | — | Widget de barra con GPU, RAM (GiB) y tok/s de vllmcritic leídos de Kairos Dash en la máquina remota; panel emergente con los colores del tema. Su `README.md` trae ajustes y detalles de implementación |
| `config/omarchy/bar/modules/system-monitor.qml` | — | Módulo QML del bar (monitor de sistema) |
| `config/omarchy/hooks/` | — | Hooks: theme-set (tahoe-dark), post-update (voxtype, agent, fingerprint) |
| `omactheme/` | `~/Projects/omactheme` | Proyecto del tema **tahoe-dark**: instalador, tema, dock, `tahoe-window`, `omarchy-dock`, mission control |
| `config/{alacritty,foot,kitty,ghostty}/` | `~/.config/...` | Terminales |
| `config/{nvim,lazygit,tmux,herdr,btop,imv,xournalpp,mise,fcitx5,git,voxtype}/` | `~/.config/...` | Herramientas de desarrollo y sistema |
| `config/wireplumber/` | `~/.config/wireplumber/` | Autoconexión A2DP Bluetooth |
| `config/systemd/user/voxtype.service` | — | Daemon de dictado por voz (push-to-talk) |
| `config/autostart/` | `~/.config/autostart/` | Entradas de autostart |
| `config/{starship.toml,mimeapps.list,xdg-terminals.list,chromium-flags.conf}` | `~/.config/` | Varios |
| `dotfiles/` | `$HOME/` | `.bashrc`, `.XCompose` |
| `local-bin/fix-resolve-dialog` | `~/.local/bin/` | Binario para arreglar el diálogo de DaVinci Resolve |
| `packages/aur.txt` | `pacman -Qm` | Paquetes AUR instalados |
| `packages/explicit.txt` | `pacman -Qqe` | Paquetes instalados explícitamente (referencia) |
| `themes.md` | — | Temas externos (repos git con su commit fijado) |

## Temas

- **tahoe-dark** (activo): se instala desde `omactheme/` con `./omactheme/install.sh`.
- **dos-moos, hermarchy, noir**: repos git externos ya en GitHub; ver `themes.md`.
  El instalador los clona en `~/.config/omarchy/themes/`.

## Mantener el backup al día

El repo es un **espejo manual**: `./sync.sh` copia desde la máquina, enseña el
diff y commitea.

```bash
cd ~/Projects/amartinomarchy
./sync.sh              # copiar + diff + pregunta antes de commitear
./sync.sh -n           # dry-run: solo dice qué cambiaría
./sync.sh --yes --push # sin preguntas y envía a GitHub
./sync.sh --watch ~/.config/hypr/extra   # sitios extra donde buscar ficheros nuevos
```

Qué descarta al añadir ficheros nuevos (por defecto solo busca en
`~/.config/omarchy`, `~/.config/hypr` y `~/.local/bin`): symlinks, shims de
mise, binarios, ficheros de más de 1 MiB, `*.sample`, `backgrounds/`,
`themes/`, cachés y lo que ya esté en el repo con otro nombre. Y tiene un freno
de secretos: no mete nada cuyo nombre o contenido parezca una credencial
(`ghp_`/`gho_`/`github_pat_`, claves privadas, tokens de Slack o AWS) — los lista
para que decidas a mano.

Los symlinks que ya hay en el repo (`config/nvim/lua/plugins/theme.lua`,
`config/btop/themes/current.theme`) apuntan a estado de la máquina y **no se
tocan**.

## Restaurar en otra máquina

Requisitos: Omarchy instalado y actualizado, `yay` disponible.

```bash
git clone https://github.com/amartinro/amartinomarchy ~/Projects/amartinomarchy
cd ~/Projects/amartinomarchy
./install.sh
```

El script:

1. Hace backup de la config existente en `~/.local/state/amartinomarchy/backups/`.
2. Copia `config/` a `~/.config/` y `dotfiles/` a `$HOME/`.
3. Instala `local-bin/` en `~/.local/bin/`.
4. Instala los paquetes AUR de `packages/aur.txt` con `yay`.
5. Clona los temas externos en `~/.config/omarchy/themes/`.
6. Ejecuta `omactheme/install.sh` (tema tahoe-dark, dock, hooks, hyprbars).
7. Ejecuta `omactheme/enable-mission-control.sh` (hymission + gestos).
8. Activa `voxtype.service` (user) y reinicia shell/Hyprland.

## Plugins Hyprland (hyprpm)

- `hyprbars` (repo `hyprland-plugins`) — lo activa `omactheme/install.sh`.
- `hymission` (repo de gfhdhytghd) — lo activa `omactheme/enable-mission-control.sh`.

## Excluido a propósito

- Datos personales y secretos: Bitwarden, Thunderbird, Todoist, `.dsh`, `.pki`,
  dconf, VS Code (`~/.config/Code`), navegadores, `.claude`/`.codex`/`.copilot`.
- `~/Projects/omacal`: proyecto de app con su propio repo git (no es config del sistema).
- `~/.config/omarchy/themes/{dos-moos,hermarchy,noir}`: ya viven en sus propios repos.
- Archivos de estado/caché (`.cache`, sockets, logs).

## Notas

- `fix-resolve-dialog` es un binario ELF compilado (20K); no hay fuente en el repo.
- El MX Master 3 necesita acceso a `/dev/input/eventN` (grupo `input`);
  `amartin.mouse-mapper` detecta el dispositivo con `mxmouse-info.sh`.
- `packages/explicit.txt` es solo referencia: Omarchy trae la base; lo crítico es `aur.txt`.