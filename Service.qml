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
    + 'if [ -f "$menu" ] && grep -q ">>> payton.logomarchy" "$menu"; then\n'
    + '  sed -i "/>>> payton\\.logomarchy/,/<<< payton\\.logomarchy/d" "$menu"\n'
    + 'fi\n'

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
