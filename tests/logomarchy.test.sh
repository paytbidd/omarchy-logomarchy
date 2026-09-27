#!/bin/bash
# Runs omarchy-logomarchy against a fake HOME and theme tree.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
BIN="$ROOT/scripts/omarchy-logomarchy"
REAL_LOGO="${OMARCHY_PATH:-/usr/share/omarchy}/logo.svg"
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export XDG_CONFIG_HOME="$HOME/.config"
export OMARCHY_PATH="$T/omarchy"
export LOGOMARCHY_LOGO="$REAL_LOGO"
unset LOGOMARCHY_BACKGROUNDS

STATE="$HOME/.local/state/omarchy/current"
BG="$XDG_CONFIG_HOME/omarchy/backgrounds"
mkdir -p "$STATE/theme/backgrounds" "$T/bin"

# Record bg-set calls instead of touching the live shell.
cat >"$T/bin/omarchy-theme-bg-set" <<EOF
#!/bin/bash
ln -nsf "\$(realpath "\$1")" "$STATE/background"
echo "\$1" >>"$T/bg-set.log"
EOF
cat >"$T/bin/omarchy-theme-bg-next" <<EOF
#!/bin/bash
echo next >>"$T/bg-set.log"
EOF
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"

make_theme() {
  local dir="$OMARCHY_PATH/themes/$1"
  mkdir -p "$dir/backgrounds"
  printf 'accent = "%s"\nbackground = "%s"\nforeground = "%s"\n' "$2" "$3" "${4:-#ffffff}" >"$dir/colors.toml"
}

use_theme() {
  echo "$1" >"$STATE/theme.name"
  rm -rf "$STATE/theme"
  cp -r "$OMARCHY_PATH/themes/$1" "$STATE/theme"
}

pixel() {
  magick "$1" -format "%[hex:p{$2,$3}]" info:
}

pass=0
check() {
  if eval "$2"; then
    pass=$((pass + 1))
  else
    echo "FAIL: $1" >&2
    exit 1
  fi
}

make_theme plain "#89b4fa" "#1e1e2e"
cat >>"$OMARCHY_PATH/themes/plain/colors.toml" <<'EOF'
muted = "#2d3450"
blue = "#3366ff"
red = "#ff3355"
EOF
make_theme stock "#81a1c1" "#2e3440"
touch "$OMARCHY_PATH/themes/stock/backgrounds/omarchy.png"
touch "$OMARCHY_PATH/themes/stock/backgrounds/1-art.png"

# Generate: colors, size, and centering.
out=$("$BIN" generate --theme plain)
check "default/dark filename" '[[ $out == "$BG/plain/omarchy-logo-default-dark.png" ]]'
check "dark background" '[[ $(pixel "$out" 0 0) == 1E1E2E* ]]'
check "default logo width" '[[ $(magick "$out" -trim -format %w info:) == 1620 ]]'
check "4K canvas" '[[ $(magick "$out" -format %wx%h info:) == 3840x2160 ]]'

out=$("$BIN" generate --theme plain --size xsmall --style accent)
check "accent background" '[[ $(pixel "$out" 0 0) == 89B4FA* ]]'
check "xsmall logo width" '[[ $(magick "$out" -trim -format %w info:) == 567 ]]'
check "previous variant replaced" '[[ $(ls "$BG/plain" | wc -l) == 1 ]]'

out=$("$BIN" generate --theme plain --size default --style light)
check "light background" '[[ $(pixel "$out" 0 0) == FFFFFF* ]]'
check "light logo" 'magick "$out" -format %c histogram:info: | grep -qi 1E1E2E'

make_theme paper "#56949f" "#faf4ed" "#575279"
out=$("$BIN" generate --theme paper --style light)
check "light field stays light" '[[ $(pixel "$out" 0 0) == FAF4ED* ]]'
check "light logo is the dark color" 'magick "$out" -format %c histogram:info: | grep -qi 575279'

out=$("$BIN" generate --theme plain --field dark --logo foreground)
check "pairing filename" '[[ $out == "$BG/plain/omarchy-logo-default-dark-foreground.png" ]]'
check "pairing logo color" 'magick "$out" -format %c histogram:info: | grep -qi FFFFFF'
check "pairing keeps dark field" '[[ $(pixel "$out" 0 0) == 1E1E2E* ]]'

check "rejects palette hue field" '! "$BIN" generate --theme plain --field blue 2>/dev/null'
check "rejects palette hue logo" '! "$BIN" generate --theme plain --logo red 2>/dev/null'

out=$("$BIN" generate --theme plain --field accent --logo accent)
check "matching colors keep the field" '[[ $(pixel "$out" 0 0) == 89B4FA* ]]'
check "matching colors move the logo" 'magick "$out" -format %c histogram:info: | grep -qi FFFFFF'

out=$("$BIN" generate --theme plain --field muted --logo accent)
check "muted field" '[[ $(pixel "$out" 0 0) == 2D3450* ]]'

check "rejects bad size" '! "$BIN" generate --theme plain --size huge 2>/dev/null'
check "rejects bad style" '! "$BIN" generate --theme plain --style neon 2>/dev/null'
check "rejects missing field color" '! "$BIN" generate --theme paper --field muted 2>/dev/null'
check "rejects path slug" '! "$BIN" generate --theme ../x 2>/dev/null'

# Auto: new theme with no backgrounds gets the logo set as wallpaper.
rm -rf "$BG"
use_theme plain
ln -nsf "$T/elsewhere.png" "$STATE/background"
"$BIN" auto plain
check "auto generates default" '[[ -f $BG/plain/omarchy-logo-default-dark.png ]]'
check "auto sets it when theme had none" 'grep -q "plain/omarchy-logo-default-dark.png" "$T/bg-set.log"'

# Auto keeps a variant the user picked.
"$BIN" generate --theme plain --size small >/dev/null
"$BIN" auto plain
check "auto keeps chosen variant" '[[ -f $BG/plain/omarchy-logo-small-dark.png && ! -f $BG/plain/omarchy-logo-default-dark.png ]]'

# Auto skips themes that ship their own logo and leaves their art up.
: >"$T/bg-set.log"
use_theme stock
ln -nsf "$STATE/theme/backgrounds/1-art.png" "$STATE/background"
"$BIN" auto stock
check "auto skips shipped logo" '[[ ! -d $BG/stock ]]'
check "auto leaves wallpaper alone" '[[ ! -s $T/bg-set.log ]]'

# Get works before any logo exists for the theme.
use_theme plain
rm -rf "$BG"
json=$("$BIN" get --json)
check "get with no logo" '[[ $(jq -r .file <<<"$json") == "" ]]'

# Get reports the current theme's variant.
"$BIN" generate --size small --style accent --set >/dev/null
json=$("$BIN" get --json)
check "get size" '[[ $(jq -r .size <<<"$json") == small ]]'
check "get style" '[[ $(jq -r .style <<<"$json") == accent ]]'
check "get field" '[[ $(jq -r .field <<<"$json") == accent ]]'
check "get logo" '[[ $(jq -r .logo <<<"$json") == background ]]'
check "get active" '[[ $(jq -r .active <<<"$json") == true ]]'
check "get offers at most 5 per group" '[[ $(jq "[.fields, .logos, .sizes | length] | max" <<<"$json") -le 5 ]]'
check "get sizes" '[[ $(jq -c "[.sizes[] | [.value, .cellPx]]" <<<"$json") == "[[\"default\",20],[\"small\",12],[\"xsmall\",7]]" ]]'
check "get pair colors" '[[ $(jq -r ".pairs[\"dark:accent\"] | .field + .logo" <<<"$json") == "#1e1e2e#89b4fa" ]]'
check "get pair resolves clash" '[[ $(jq -r ".pairs[\"accent:accent\"].logo" <<<"$json") == "#ffffff" ]]'
check "get logo svg" '[[ $(jq -r .logoSvg <<<"$json") == "<svg"* ]]'

json=$(use_theme paper; "$BIN" get --json)
check "get hides muted when theme lacks it" '[[ $(jq -r "[.fields[].value] | index(\"muted\")" <<<"$json") == null ]]'
use_theme plain

# Remove clears the file and moves off it.
"$BIN" remove
check "remove deletes files" '[[ ! -d $BG/plain ]]'
check "remove moves to next background" '[[ $(tail -n1 "$T/bg-set.log") == next ]]'

mkdir -p "$BG/plain"
touch "$BG/plain/omarchy-logo-xsmall-light.png"
json=$("$BIN" get --json)
check "legacy light field" '[[ $(jq -r .field <<<"$json") == light ]]'
check "legacy light logo" '[[ $(jq -r .logo <<<"$json") == contrast ]]'

echo "ok - $pass checks"
