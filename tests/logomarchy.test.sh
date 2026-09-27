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
check "default/dark filename" '[[ $out == "$BG/plain/logomarchy-default-dark.png" ]]'
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
check "pairing filename" '[[ $out == "$BG/plain/logomarchy-default-dark-foreground.png" ]]'
check "pairing logo color" 'magick "$out" -format %c histogram:info: | grep -qi FFFFFF'
check "pairing keeps dark field" '[[ $(pixel "$out" 0 0) == 1E1E2E* ]]'

out=$("$BIN" generate --theme plain --field blue --logo red)
check "hue field" '[[ $(pixel "$out" 0 0) == 3366FF* ]]'
check "hue logo" 'magick "$out" -format %c histogram:info: | grep -qi FF3355'

# Themes derived from alacritty.toml only have ANSI slots.
make_theme ansi "#d66b6b" "#1b1112"
printf 'color1 = "#b44a4a"\ncolor4 = "#4a6ab4"\n' >>"$OMARCHY_PATH/themes/ansi/colors.toml"
out=$("$BIN" generate --theme ansi --field blue --logo red)
check "ansi slot field" '[[ $(pixel "$out" 0 0) == 4A6AB4* ]]'
check "ansi slot logo" 'magick "$out" -format %c histogram:info: | grep -qi B44A4A'
check "rejects unknown color" '! "$BIN" generate --theme plain --field teal 2>/dev/null'

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
check "auto generates default" '[[ -f $BG/plain/logomarchy-default-dark.png ]]'
check "auto sets it when theme had none" 'grep -q "plain/logomarchy-default-dark.png" "$T/bg-set.log"'

# Auto keeps a variant the user picked.
"$BIN" generate --theme plain --size small >/dev/null
"$BIN" auto plain
check "auto keeps chosen variant" '[[ -f $BG/plain/logomarchy-small-dark.png && ! -f $BG/plain/logomarchy-default-dark.png ]]'

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
check "get primaries at most 5" '[[ $(jq "[.fields, .logos | map(select(.group==\"primary\")) | length] | max" <<<"$json") -le 5 ]]'
check "get hue secondaries" '[[ $(jq -c "[.fields[] | select(.group==\"secondary\") | .value]" <<<"$json") == "[\"red\",\"blue\"]" ]]'
check "get dedupes colors" '[[ $(jq "[.logos[].hex | ascii_downcase] | length == (unique | length)" <<<"$json") == true ]]'
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
touch "$BG/plain/logomarchy-xsmall-light.png"
json=$("$BIN" get --json)
check "legacy light field" '[[ $(jq -r .field <<<"$json") == light ]]'
check "legacy light logo" '[[ $(jq -r .logo <<<"$json") == contrast ]]'

# Setup wires the hook and a menu row that the shell's parser accepts.
MENU="$XDG_CONFIG_HOME/omarchy/extensions/omarchy-menu.jsonc"
HOOK="$XDG_CONFIG_HOME/omarchy/hooks/theme-set.d/payton.logomarchy"

menu_parses() {
  node -e '
    const raw = require("fs").readFileSync(process.argv[1], "utf8")
    const s = raw.replace(/^\s*\/\/[^\n]*(\n|$)/gm, "").replace(/,(\s*[}\]])/g, "$1")
    const o = JSON.parse(s)
    if (typeof o !== "object" || o === null) process.exit(1)
  ' "$MENU" 2>/dev/null || python3 - "$MENU" <<'EOF'
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
json.loads(re.sub(r",(\s*[}\]])", r"\1", raw))
EOF
}

menu_keys() {
  python3 - "$MENU" <<'EOF'
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r"^\s*//[^\n]*(\n|$)", "", raw, flags=re.M)
print(" ".join(json.loads(re.sub(r",(\s*[}\]])", r"\1", raw)).keys()))
EOF
}

rm -rf "$BG"
mkdir -p "${MENU%/*}"
cat >"$MENU" <<'EOF'
{
  // user comment
  "personal": {"icon":"","label":"Personal"},
  "personal.notes": {"icon":"","label":"Notes","action":"notes"}
}
EOF
"$BIN" setup
check "setup installs hook" '[[ -x $HOOK ]]'
check "setup menu parses" 'menu_parses'
check "setup keeps user rows" '[[ $(menu_keys) == "style.logomarchy personal personal.notes" ]]'
check "setup adds the row" 'grep -q "\"label\": \"Logomarchy\"" "$MENU"'
check "setup keeps comments" 'grep -q "// user comment" "$MENU"'
check "setup row points at plugin" 'grep -q "$ROOT/scripts/omarchy-logomarchy.* panel" "$MENU"'
check "setup makes a wallpaper" '[[ -f $BG/plain/logomarchy-default-dark.png ]]'

before=$(cat "$MENU")
"$BIN" setup
check "setup is idempotent" '[[ $(cat "$MENU") == "$before" ]]'

# The service's inline teardown, which runs without the plugin folder.
sed "/>>> payton\.logomarchy/,/<<< payton\.logomarchy/d" "$MENU" >"$T/menu-sed"
check "sed teardown leaves valid menu" 'MENU="$T/menu-sed" menu_parses && [[ $(MENU="$T/menu-sed" menu_keys) == "personal personal.notes" ]]'

"$BIN" teardown
check "teardown removes hook" '[[ ! -e $HOOK ]]'
check "teardown removes row" '[[ $(menu_keys) == "personal personal.notes" ]] && ! grep -q logomarchy "$MENU"'
check "teardown keeps wallpapers" '[[ -f $BG/plain/logomarchy-default-dark.png ]]'

"$BIN" teardown --purge
check "purge deletes wallpapers" '[[ ! -d $BG/plain ]]'

# Things the plugin did not write are never changed or removed.
cat >"$MENU" <<'EOF'
{
  "style.logomarchy": {"icon":"x","label":"Mine","action":"mine"},
}
EOF
before=$(cat "$MENU")
printf '#!/bin/bash\necho mine\n' >"$HOOK"
mkdir -p "$BG/plain"
echo "user file" >"$BG/plain/omarchy-logo-mine.png"
"$BIN" setup 2>/dev/null
check "setup keeps a user's same-named row" '[[ $(cat "$MENU") == "$before" ]]'
check "setup keeps a user's hook" '[[ $(cat "$HOOK") == *"echo mine"* ]]'
"$BIN" teardown --purge
check "teardown keeps a user's hook" '[[ -f $HOOK ]]'
check "teardown keeps a user's row" '[[ $(cat "$MENU") == "$before" ]]'
check "purge keeps unrelated wallpapers" '[[ -f $BG/plain/omarchy-logo-mine.png ]]'
"$BIN" remove --theme plain
check "remove keeps unrelated wallpapers" '[[ -f $BG/plain/omarchy-logo-mine.png ]]'
rm -f "$HOOK" "$BG/plain/omarchy-logo-mine.png"

# The pre-1.0.1 hook name is cleaned up only when it is ours.
OLD_HOOK="${HOOK%/*}/logomarchy"
cp "$ROOT/hooks/payton.logomarchy" "$OLD_HOOK"
rm -f "$MENU"
"$BIN" setup
check "setup removes our old hook" '[[ ! -e $OLD_HOOK && -x $HOOK ]]'
printf '#!/bin/bash\necho other\n' >"$OLD_HOOK"
"$BIN" teardown
check "teardown keeps a user's old-named hook" '[[ -f $OLD_HOOK ]]'
rm -f "$OLD_HOOK"

rm -f "$MENU"
"$BIN" setup
check "setup creates menu file" 'menu_parses && [[ $(menu_keys) == "style.logomarchy" ]]'

echo '{ "a": {' >"$MENU"
check "setup leaves broken menu alone" '"$BIN" setup 2>/dev/null; [[ $(cat "$MENU") == "{ \"a\": {" ]]'

echo "ok - $pass checks"
