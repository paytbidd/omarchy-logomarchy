# Logomarchy

[Omarchy](https://omarchy.org/) logo wallpaper in any theme's colors, including themes that don't ship one.

![Sizes and styles in Catppuccin](preview.png)

Every time you switch themes, a theme-set hook checks for an Omarchy logo wallpaper. If the theme has none, it makes one from `colors.toml` in the same size and colors as the stock ones: theme background with an accent-colored logo. If the theme has no backgrounds at all, the logo is also set as the wallpaper.

Themes that already ship an Omarchy logo wallpaper are left alone, unless you pick a size or colors for them yourself.

To change the logo on the current theme, open **Style › Logomarchy** in the Omarchy menu:

- **Size:** Default, Small, Extra small
- **Field:** the wallpaper color. Dark, Muted, Light, and Accent, plus any of the theme's red, orange, yellow, green, cyan, blue, and magenta that `colors.toml` defines
- **Logo:** the mark. Accent, Contrast (the theme's darker color), Foreground, Background, and those same palette colors

Dark with an accent logo matches the stock wallpapers. Light with Contrast puts the lighter of the theme's background and foreground behind the mark and the darker color on it. Accent with a background logo fills the screen with the accent. A swatch only appears when the theme has that color. If the field and the logo would be the same color, the mark falls back to one that still shows.

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
omarchy-logomarchy generate [--theme <slug>] [--size default|small|xsmall] [--field <color>] [--logo <color>] [--style dark|light|accent|<logo>] [--set]
omarchy-logomarchy auto [<slug>]      # what the hook runs
omarchy-logomarchy remove [--theme <slug>]
omarchy-logomarchy get [--json]
omarchy-logomarchy panel
```

Files go to `~/.config/omarchy/backgrounds/<theme>/omarchy-logo-<size>-<colors>.png` (3840×2160). The original three keep the short names `dark`, `light`, and `accent`; other pairings are named `field-logo`, such as `dark-blue`. Nothing inside a theme is modified, so `omarchy theme bg next` cycles through the logo along with the theme's own art.

Needs `rsvg-convert` and `magick`, both included in Omarchy.

## Tests

```bash
tests/logomarchy.test.sh
```
