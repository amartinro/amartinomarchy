# Tahoe Dark for Omarchy

An original dark Omarchy theme inspired by macOS Tahoe's restrained Liquid
Glass language. It themes the Omarchy shell, Hyprland window chrome, motion,
menus, notifications, terminal palette, wallpaper, and the existing local dock.

The three window controls are functional: red closes, yellow toggles the active
window between floating and tiled, and green toggles maximize. Double-clicking
a titlebar also toggles maximize. The dock magnifies on hover, uses a translucent
glass surface, and keeps running-app indicators.

## Install

```bash
./install.sh
```

If fingerprint authentication times out in a non-interactive launcher, finish
from a normal terminal with `./finish-install.sh`.

## Mission Control and multitouch gestures

Install the maintained Hymission overview integration from a normal terminal:

```bash
./enable-mission-control.sh
```

- Three-finger horizontal swipe changes workspace with direct 1:1 tracking.
- Four-finger swipe up opens Mission Control with continuous tracking; swipe
  down dismisses it (and pulling back cancels the gesture).
- `F3` or `Super+grave` toggles the overview without a touchpad.
- Click a live window or workspace preview to select it; `Esc` cancels.

The installer backs up every user file it replaces under
`~/.local/state/omactheme/backups/`, installs the official `hyprbars` plugin if
needed, installs the theme and dock integration, then activates `tahoe-dark`.

## Remove

```bash
./uninstall.sh
```

This restores the latest installer backup and switches back to the theme that
was active before installation.
