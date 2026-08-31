# Temas externos

Temas que viven en sus propios repos git (ya en GitHub) y se clonan en
`~/.config/omarchy/themes/` al restaurar. El commit fijado es el que estaba
activo en la máquina de origen.

| Tema | Repo | Commit |
|------|------|--------|
| dos-moos | https://github.com/HANCORE-linux/omarchy-dos-moos-theme | `85ed3d2` |
| hermarchy | https://github.com/archer-clawbot/omarchy-hermarchy-theme | `12f3c52` |
| noir | https://github.com/tahadx/omarchy-noir-theme | `42a6852` |

El tema **tahoe-dark** no está aquí: se genera desde `omactheme/`
(`./omactheme/install.sh` lo copia a `~/.config/omarchy/themes/tahoe-dark`).

Para actualizar un tema a la última versión:

```bash
git -C ~/.config/omarchy/themes/<tema> pull
omarchy theme set <tema>
```