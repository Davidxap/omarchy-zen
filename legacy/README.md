# Zen Auto Style — Legacy Extension

This directory contains the original extension-based implementation of Zen Auto
Style by **Gregory Strand** ([gstrand99](https://github.com/gstrand99)), preserved
here for reference. It is **not installed** by the current `install.sh`.

## What this was

The original approach used a Firefox experiment extension (`.xpi`) plus a
Python native-messaging host to achieve live stylesheet reload without
restarting Zen. It worked as follows:

1. Omarchy renders `~/.config/omarchy/current/theme/custom-zen.css`.
2. The native host detects Omarchy's `light.mode` marker and adds the matching
   `color-scheme` to the generated stylesheet.
3. Zen loads the generated variables through its profile CSS.
4. Omarchy runs the installed `theme-set.d` hook after each theme change.
5. The hook touches `~/.cache/zen-auto-style/reload`.
6. A native-messaging host sends the current stylesheet text to the extension.
7. The extension replaces its registered author stylesheet in Zen.

The host also watched the generated stylesheet directly, so
`omarchy theme refresh` and direct regeneration were detected even if the hook
was skipped. Themes containing `light.mode` used a light color scheme; all other
themes used dark.

## Why it was replaced

This approach required two security-sensitive preferences:

- `xpinstall.signatures.required = false` — allowed unsigned extensions to be
  installed.
- `extensions.experiments.enabled = true` — enabled privileged experiment APIs.

The current CSS-only install path (described in the project root
[README.md](../README.md)) achieves the same themed result without either of
these trade-offs.

## Files

| File | Purpose |
| --- | --- |
| `manifest.json.in` | Extension manifest template (experiment API + nativeMessaging) |
| `background.js.in` | Background script connecting to the native host |
| `build.sh` | Builds the `.xpi` from templates |
| `project.conf` | Extension ID and native host name defaults |
| `native/zen-auto-style-host.py` | Python native-messaging host (polling) |
| `native/native-host.json.in` | Native-host manifest template |
| `api/style-reloader/schema.json` | Experiment API schema |
| `api/style-reloader/implementation.js` | Experiment API implementation (nsIStyleSheetService) |

## Original credits

Original implementation by Gregory Strand, released under the MIT License.
Omarchy 4.x compatibility patches and the CSS-only redesign by David Arturo
Arroyave Pérez.
