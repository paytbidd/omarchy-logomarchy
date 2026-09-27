# Logomarchy

[Omarchy](https://omarchy.org/) logo wallpaper in any theme's colors, including themes that don't ship one.

![Sizes and styles in Catppuccin](preview.png)

Every time you switch themes, a theme-set hook checks for an Omarchy logo wallpaper. If the theme has none, it makes one from `colors.toml` in the same size and colors as the stock ones: theme background with an accent-colored logo. If the theme has no backgrounds at all, the logo is also set as the wallpaper.

Themes that already ship an Omarchy logo wallpaper are left alone, unless you pick a size or style for them yourself.

To change the logo on the current theme, open **Style › Logomarchy** in the Omarchy menu:

- **Size:** Default, Small, Extra small
- **Style:** Dark (theme background, accent logo) or Accent (accent background, logo in the theme's background color, so it comes out dark on dark themes and light on light ones)

Each theme remembers its own choice.

## Install

```bash
git clone https://github.com/paytbidd/omarchy-logomarchy.git ~/.config/omarchy/plugins/payton.logomarchy
~/.config/omarchy/plugins/payton.logomarchy/install
```

`install` adds the plugin, installs the `theme-set` hook, and makes a logo wallpaper for the current theme.

Add a menu entry in `~/.config/omarchy/extensions/omarchy-menu.jsonc`:

```jsonc
"style.logomarchy": {
  "icon": "󰸉",
  "label": "Logomarchy",
  "description": "Omarchy logo wallpaper in this theme's colors",
  "aliases": ["logomarchy", "logo wallpaper"],
  "action": "~/.config/omarchy/plugins/payton.logomarchy/scripts/omarchy-logomarchy panel"
}
```

## Remove

```bash
~/.config/omarchy/plugins/payton.logomarchy/uninstall
omarchy plugin remove payton.logomarchy
```

## CLI

```bash
omarchy-logomarchy generate [--theme <slug>] [--size default|small|xsmall] [--style dark|accent] [--set]
omarchy-logomarchy auto [<slug>]      # what the hook runs
omarchy-logomarchy remove [--theme <slug>]
omarchy-logomarchy get [--json]
omarchy-logomarchy panel
```

Files go to `~/.config/omarchy/backgrounds/<theme>/omarchy-logo-<size>-<style>.png` (3840×2160), the folder Omarchy already uses for extra backgrounds per theme. Nothing inside a theme is modified, so `omarchy theme bg next` cycles through the logo along with the theme's own art.

Needs `rsvg-convert` and `magick`, both included in Omarchy.

## Tests

```bash
tests/logomarchy.test.sh
```
