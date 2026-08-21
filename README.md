# Zen Auto Style

Synchronizes Omarchy's Pywal-generated color theme into Zen Browser using profile
CSS. No extension, no native host, no privileged experiment APIs — just a managed
symlink, a couple of `@import` lines, and the stylesheet Omarchy already generates.

> **Fork of [gstrand99/zen-auto-style](https://github.com/gstrand99/zen-auto-style)**
> by Gregory Strand, originally released under the MIT License. This fork adapts
> the project for Omarchy 4.x compatibility and simplifies the install path to a
> pure CSS approach. The original extension-based implementation is preserved in
> [`legacy/`](legacy/) for reference. See [`legacy/README.md`](legacy/README.md)
> for the original documentation.

## Why a CSS-only approach?

The original project used a Firefox experiment extension (`.xpi`) plus a
native-messaging host written in Python to achieve live theme reload. That
required:

- `xpinstall.signatures.required = false` (disable signature enforcement)
- `extensions.experiments.enabled = true` (enable privileged experiment APIs)

Both weaken Zen Browser's security posture. This fork replaces that with a
simple symlink chain: Omarchy generates the stylesheet, and Zen reads it
through its profile CSS. The result is the same themed Zen experience without
installing any extension, running any background process, or disabling any
security preference.

The only preference required is
`toolkit.legacyUserProfileCustomizations.stylesheets = true`, which is the
standard Mozilla-recommended way to load `userChrome.css` / `userContent.css`.

## Requirements

- Omarchy with the `omarchy` command available
- Zen Browser installed and opened at least once
- Bash
- Standard command-line tools: `awk`, `grep`, `sed`, `install`, and `mktemp`

On Omarchy/Arch Linux these are already present. No `python`, `zip`, `unzip`, `jq`,
or `ripgrep` are required for the CSS-only install path.

## Quick start

```bash
git clone https://github.com/Davidxap/zen-auto-style.git
cd zen-auto-style
chmod +x check.sh install.sh uninstall.sh
./check.sh
./install.sh
```

`install.sh` installs the Omarchy color template and theme hook, wires the generated
stylesheet into Zen's profile CSS, and enables legacy user-profile stylesheets. By
default it applies a stock Zen layout with only palette and compatibility styling.

Then:

1. Restart Zen once so it picks up the new `userChrome.css` / `userContent.css`.
2. Run `omarchy theme set <theme-name>` to test that the colors update.
3. Restart Zen again to see the regenerated palette reflected in the UI.

No extension needs to be installed in `about:addons`. No signature enforcement is
disabled. No experiment APIs are used.

## How it works

1. Omarchy renders `custom-zen.css` from the installed `custom-zen.css.tpl` using
   the current Pywal palette. On Omarchy 4.x this lives under
   `~/.local/state/omarchy/current/theme/`; on older layouts it lives under
   `~/.config/omarchy/current/theme/`.
2. The installer symlinks that generated file into the Zen profile's `chrome/`
   directory as `custom-zen.css`.
3. Managed `@import` lines in `userChrome.css` and `userContent.css` load the
   themed variables and the companion chrome/content stylesheets.
4. The `light.mode` marker emitted by Omarchy drives a `color-scheme` rule that
   is appended to the generated CSS at render time.
5. `omarchy theme refresh` regenerates the stylesheet, and because Zen reads it
   through a symlink, the next restart picks up the new palette automatically.

No native-messaging host and no background script are involved in the CSS-only
install path. Zen simply reloads its profile CSS on restart, which reads the
symlinked stylesheet that Omarchy keeps up to date.

## Installed components

- `~/.config/omarchy/themed/custom-zen.css.tpl` — the Pywal-driven template
- `~/.config/omarchy/hooks/theme-set.d/zen-auto-style` — a hook reserved for
  future live-reload enhancements
- Zen profile `chrome/zen-auto-style-chrome.css`
- Zen profile `chrome/zen-auto-style-content.css`
- Zen profile `chrome/zen-auto-style-mods.css`
- Zen profile `chrome/zen-auto-style-mods/`
- Zen profile `chrome/custom-zen.css` — symlink to Omarchy's generated stylesheet
- Managed `@import` blocks in `userChrome.css` and `userContent.css`
- `user_pref("toolkit.legacyUserProfileCustomizations.stylesheets", true)` in the
  profile's `user.js` (the only preference required for profile CSS to work)

The installer reads Zen's selected profile from `installs.ini`, falling back to
`profiles.ini`. It checks `~/.zen` as well as `~/.config/zen`, so older Zen root
installs are detected automatically.

Set `ZEN_PROFILE=/absolute/profile/path` to override profile discovery.

## Optional Zen mods

Core styling only changes Zen's colors and themes its internal pages. It also
keeps a popup compatibility fix that prevents dark popup backgrounds from being
combined with unreadable text. Layout and visual-affordance changes are separate
optional mods.

Available mods:

| Mod | Effect |
| --- | --- |
| `compact-rounded-content` | Uses 8px element spacing and 10px webview corners |
| `flat-sidebar` | Removes sidebar and content-panel shadows |
| `sidebar-splitter-hover` | Adds a visible animated sidebar splitter hover state |
| `unloaded-tabs` | Makes unloaded tabs grayscale and partially transparent |

Install stock themed Zen with no optional mods:

```bash
./install.sh
```

Install every optional mod:

```bash
ZEN_AUTO_STYLE_MODS=all ./install.sh
```

Install selected mods:

```bash
ZEN_AUTO_STYLE_MODS='sidebar-splitter-hover,unloaded-tabs' ./install.sh
```

Re-running the installer regenerates `zen-auto-style-mods.css`, so the same
commands can be used to change or remove the selected mods later. Use
`ZEN_AUTO_STYLE_MODS=none` explicitly when scripting a stock-only installation.

## Installation details

The installer preserves existing profile CSS and prepends imports for the
managed files. Files changed or replaced during installation are backed up
under `~/.local/state/zen-auto-style/backups`.

The installer reads Zen's selected profile from `installs.ini` (falling back to
`profiles.ini`) under `~/.zen` or `~/.config/zen`. To override discovery:

```bash
ZEN_PROFILE="$HOME/.config/zen/example.default" ./install.sh
```

The installer also cleans up artifacts left by the legacy extension-based install:
the native-host manifest, the old `~/.local/lib/zen-auto-style` host, the cache
directory, and the `extensions.experiments.enabled` and
`xpinstall.signatures.required` preferences that the old approach required. Only
`toolkit.legacyUserProfileCustomizations.stylesheets` is kept, because it is the
single preference needed for profile CSS to be loaded.

## Uninstall

```bash
./uninstall.sh
```

The uninstall script removes the Omarchy hook, managed browser files, the
`@import` blocks it added, and the legacy stylesheet preference. CSS outside
those blocks is preserved. The Omarchy template is removed only if it still
matches the version shipped by this repository. Legacy native-host and extension
artifacts are also cleaned up if present.

## The legacy extension

The original extension-based implementation — a Firefox experiment extension
(`.xpi`) plus a Python native-messaging host for live stylesheet reload — is
preserved in [`legacy/`](legacy/). It is not installed by `install.sh` but is
kept for reference and for anyone who prefers the live-reload approach despite
its security trade-offs. See [`legacy/README.md`](legacy/README.md) for the
original documentation by Gregory Strand.

## Credits

- **Gregory Strand** ([gstrand99](https://github.com/gstrand99)) — original
  author of [zen-auto-style](https://github.com/gstrand99/zen-auto-style),
  including the Omarchy template, Zen CSS assets, install/uninstall scripts,
  and the extension-based live-reload implementation.
- **David Arturo Arroyave Pérez** ([Davidxap](https://github.com/Davidxap)) —
  Omarchy 4.x compatibility, CSS-only install path, and project restructuring.

## License

Zen Auto Style is available under the [MIT License](LICENSE).
