import QtQuick
import Quickshell
import Quickshell.Io

// Omarchy Zen — service plugin
// Ensures the Omarchy → Zen CSS bridge is installed and refreshed.
//
// Install mechanism is pure CSS: a template rendered by Omarchy + a symlink
// into the Zen profile's chrome/. No extension, no native host, no
// xpinstall.signatures.required. The only pref required is
// toolkit.legacyUserProfileCustomizations.stylesheets.
//
// This service auto-runs the installer on shell start and on enable.
// Disable/Remove leaves the theme wiring intact — run uninstall.sh to revert.
Item {
    id: root

    // Injected by omarchy-shell's plugin loader
    property var shell: null
    property var manifest: null

    readonly property string pluginId: (manifest && manifest.id) ? String(manifest.id) : "io.github.davidxap.omarchy-zen"
    readonly property string pluginDir: (manifest && manifest.__sourceDir) ? String(manifest.__sourceDir) : localPath(Qt.resolvedUrl("./"))
    readonly property string installScript: pluginDir + "/install.sh"
    readonly property string hookSource: pluginDir + "/omarchy/theme-set-hook"
    readonly property string homeDir: Quickshell.env("HOME")

    function localPath(url) {
        var v = String(url || "")
        if (v.indexOf("file://") === 0) v = v.slice(7)
        try { return decodeURIComponent(v) } catch (e) { return v }
    }

    // Ensures the bridge is installed. Safe to re-run — install.sh is idempotent.
    function ensureInstalled() {
        if (installer.running) return
        installer.command = ["bash", installScript]
        installer.running = true
    }

    // Lightweight watcher: when Omarchy refreshes the theme, Zen's symlink
    // already points to the new file. No restart logic here — user restarts
    // Zen to pick up new CSS (documented). This hook could later send a
    // notification via qs.Commons.
    Process {
        id: installer
        stdout: StdioCollector { id: installerOut; waitForEnd: true }
        stderr: StdioCollector { id: installerErr; waitForEnd: true }
        onExited: function(exitCode, exitStatus) {
            if (exitCode !== 0) {
                console.warn("Omarchy Zen: install.sh failed (" + exitCode + "): " + installerErr.text.trim())
            } else {
                var out = installerOut.text.trim()
                if (out.length > 0) console.log("Omarchy Zen: " + out.split("\n").slice(-2).join(" — "))
            }
        }
    }

    // Deferred startup so the shell finishes loading before we touch the profile.
    Timer {
        id: startupTimer
        interval: 1500
        repeat: false
        onTriggered: root.ensureInstalled()
    }

    Component.onCompleted: startupTimer.start()

    // On disable/removal we do NOT auto-uninstall the CSS wiring — that would
    // surprise users who still want their Zen themed. Cleanup is explicit:
    //   omarchy plugin remove io.github.davidxap.omarchy-zen
    //   ~/.config/omarchy/plugins/io.github.davidxap.omarchy-zen/uninstall.sh
    // Or from the cloned repo: ./uninstall.sh
    Component.onDestruction: {
        // No detached uninstall — leave wiring intact. See README.md#uninstall.
    }
}
