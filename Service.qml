import QtQuick
import Quickshell

// Omarchy has no install hook and no manifest field for menu rows, so the
// enabled plugin wires itself up here: the theme-set hook, the Style ›
// Logomarchy row, and a logo wallpaper for the current theme.
QtObject {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  // From this file's URL: the shell strips the source dir from the manifest
  // it hands third-party plugins.
  readonly property string bin: {
    var s = String(Qt.resolvedUrl("scripts/omarchy-logomarchy"))
    return s.indexOf("file://") === 0 ? decodeURIComponent(s.substring(7)) : ""
  }
  readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")

  // The service is also torn down on shell restart and logout, so this waits
  // for the shell to record the change and only cleans up when the plugin
  // really is disabled (gone from shell.json) or deleted. It is inline so it
  // still runs after `omarchy plugin remove` deletes the plugin folder.
  readonly property string teardownScript:
      'sleep 2\n'
    + 'if [ -x "$1" ] && jq -e \'any(.plugins[]?; .id == "payton.logomarchy")\' "$2/omarchy/shell.json" >/dev/null 2>&1; then exit 0; fi\n'
    + 'for hook in "$2/omarchy/hooks/theme-set.d/payton.logomarchy" "$2/omarchy/hooks/theme-set.d/logomarchy"; do\n'
    + '  if [ -f "$hook" ] && [ ! -L "$hook" ] && grep -qF "payton.logomarchy/scripts/omarchy-logomarchy" "$hook"; then rm -f "$hook"; fi\n'
    + 'done\n'
    + 'menu="$2/omarchy/extensions/omarchy-menu.jsonc"\n'
    + 'python3 - "$menu" <<\'PY\'\n'
    + 'import json, os, re, sys\n'
    + 'from pathlib import Path\n'
    + 'path = Path(sys.argv[1])\n'
    + 'if not path.is_file():\n'
    + '    sys.exit(0)\n'
    + 'raw = path.read_text(encoding="utf-8")\n'
    + 'pat = re.compile(r"^[ \\t]*// >>> payton\\.logomarchy.*?^[ \\t]*// <<< payton\\.logomarchy[^\\n]*\\n?", re.M | re.S)\n'
    + 'text = pat.sub("", raw)\n'
    + 'if text == raw:\n'
    + '    sys.exit(0)\n'
    + 'def parses(s):\n'
    + '    s = re.sub(r"^\\s*//[^\\n]*(\\n|$)", "", s, flags=re.M)\n'
    + '    s = re.sub(r",(\\s*[}\\]])", r"\\1", s).strip()\n'
    + '    if not s:\n'
    + '        return True\n'
    + '    try:\n'
    + '        return isinstance(json.loads(s), dict)\n'
    + '    except ValueError:\n'
    + '        return False\n'
    + 'if not parses(raw) or not parses(text):\n'
    + '    sys.exit(0)\n'
    + 'if path.is_symlink():\n'
    + '    with open(path, "w", encoding="utf-8") as fh:\n'
    + '        fh.write(text)\n'
    + 'else:\n'
    + '    tmp = path.with_name("." + path.name + ".tmp")\n'
    + '    tmp.write_text(text, encoding="utf-8")\n'
    + '    os.replace(tmp, path)\n'
    + 'PY\n'

  property bool started: false

  Component.onCompleted: {
    if (bin === "") return
    started = true
    Quickshell.execDetached([bin, "setup"])
  }

  Component.onDestruction: {
    if (!started) return
    Quickshell.execDetached(["sh", "-c", teardownScript, "sh", bin, configHome])
  }
}
