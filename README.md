# Zen Auto Style

Provides complete Omarchy theme synchronization for Zen Browser, including the
Zen interface theme, internal pages, generated Omarchy color template, and live
stylesheet updates without restarting Zen.

## Requirements

- Omarchy with the `omarchy` command available
- Zen Browser installed and opened at least once
- Bash
- Python 3
- `zip`
- `unzip`
- `jq`
- `ripgrep`
- Standard command-line tools: `awk`, `grep`, `sed`, `install`, and `mktemp`

On Omarchy/Arch Linux, install the explicit build dependencies with:

```bash
sudo pacman -S --needed python zip unzip jq ripgrep
```

## Quick start

```bash
git clone https://github.com/gstrand99/zen-auto-style.git
cd zen-auto-style
chmod +x build.sh check.sh install.sh uninstall.sh
./check.sh
./install.sh
```

`install.sh` builds `build/zen-auto-style.xpi`, configures the native host, installs
the Omarchy template and hook, and updates the active Zen profile. By default,
it installs a stock Zen layout with only palette and compatibility styling.

Then:

1. Open Zen.
2. Open `about:addons`.
3. Install `build/zen-auto-style.xpi`.
4. Restart Zen once.
5. Run `omarchy theme set <theme-name>` to test live synchronization.

This extension uses a privileged Firefox experiment API. Zen must permit the
XPI to be installed. The installer enables Zen's extension experiment support
and permits unsigned extensions in the selected profile. Disabling signature
enforcement allows any unsigned extension to be installed, so only install
extensions you trust.

## Omarchy 4.x compatibility

This fork detects the Omarchy theme directory at runtime, supporting both
layouts:

| Omarchy version | Theme directory |
| --- | --- |
| 4.x (Quattro) | `~/.local/state/omarchy/current/theme/` |
| 3.x and earlier | `~/.config/omarchy/current/theme/` |

The installer also falls back to the legacy `~/.zen/` profile root when the
standard `~/.config/zen/` directory does not contain a valid profile. This
covers older Zen Browser installations and the `zen-browser-bin` AUR package.

No `ZEN_PROFILE` override is needed in most cases.

## How it works

1. Omarchy renders the active theme's `custom-zen.css` into the current theme
   directory (auto-detected between `~/.local/state/` and `~/.config/`).
2. The native host detects Omarchy's `light.mode` marker and adds the matching
   `color-scheme` to the generated stylesheet.
3. Zen loads the generated variables through its profile CSS.
4. Omarchy runs the installed `theme-set.d` hook after each theme change.
5. The hook touches `~/.cache/zen-auto-style/reload`.
6. A native-messaging host sends the current stylesheet text to the extension.
7. The extension replaces its registered author stylesheet in Zen.

The host also watches the generated stylesheet itself, so `omarchy theme refresh`
and direct regeneration are detected even if the hook is skipped. Themes
containing `light.mode` use a light color scheme; all other themes use dark.

## Security notes

This extension requires two preferences to be set in the active Zen profile:

| Preference | Purpose |
| --- | --- |
| `xpinstall.signatures.required` | Allows unsigned extensions (required for the experiment API) |
| `extensions.experiments.enabled` | Enables privileged extension APIs |

**What this means**: with `xpinstall.signatures.required` set to `false`, Zen
will accept any unsigned extension in the selected profile. This is the same
trade-off that Zen Browser itself makes for its built-in mods system.

**Mitigations**:

- Only install extensions you trust. Keep uBlock Origin or a similar content
  blocker active.
- The profile preference is scoped to a single profile, not all of Zen.
- The extension requests only `nativeMessaging` permission — it cannot read
  your tabs, history, bookmarks, or web content.
- The generated content CSS is explicitly scoped to `about:` pages via
  `@-moz-document` and does not touch website content.

## Installed components

- `~/.config/omarchy/themed/custom-zen.css.tpl`
- `~/.config/omarchy/hooks/theme-set.d/zen-auto-style`
- Zen profile `chrome/zen-auto-style-chrome.css`
- Zen profile `chrome/zen-auto-style-content.css`
- Zen profile `chrome/zen-auto-style-mods.css`
- Zen profile `chrome/zen-auto-style-mods/`
- Zen profile `chrome/custom-zen.css` symlink
- Imports in existing `userChrome.css` and `userContent.css`
- The legacy profile stylesheet preference in the profile's `user.js`
- A generated native-host manifest under `~/.mozilla/native-messaging-hosts`
- `~/.local/lib/zen-auto-style/zen-auto-style-host.py`

The installer reads Zen's selected profile from `~/.config/zen/installs.ini`
with an automatic fallback to `~/.zen/`. Set `ZEN_PROFILE=/absolute/profile/path`
to override profile discovery.

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

## Generated identifiers

The committed source uses distribution-safe defaults from `project.conf`:

```text
EXTENSION_ID=zen-auto-style@omarchy.local
NATIVE_HOST_NAME=org.omarchy.zen_auto_style
```

`build.sh` generates the real extension manifest, background script, identifier
metadata, and XPI in `build/`. Everything in that directory except `.keep` is
ignored by Git. `install.sh` uses the same generated identifiers for the
native-host manifest, preventing extension/host mismatches.

Distributors can override the identifiers without editing source:

```bash
ZEN_AUTO_STYLE_EXTENSION_ID='zen-auto-style@example.org' \
ZEN_AUTO_STYLE_NATIVE_HOST_NAME='org.example.zen_auto_style' \
./install.sh
```

The native host name may contain only letters, numbers, underscores, and
periods. Keep both identifiers stable after distributing an XPI because they
are part of the extension/native-host trust relationship.

## Installation details

The installer preserves existing profile CSS and prepends imports for the
managed files. Files changed or replaced during installation are backed up
under `~/.local/state/zen-auto-style/backups`.

The installer reads Zen's selected profile from `~/.config/zen/installs.ini`
with an automatic fallback to `~/.zen/`. To override discovery:

```bash
ZEN_PROFILE="$HOME/.zen/profile-name-here" ./install.sh
```

## Troubleshooting

Verify the native host is running:

```bash
pgrep -f zen-auto-style-host
```

If the host is not running, check that the extension is enabled in
`about:addons` and that the manifest exists:

```bash
ls ~/.mozilla/native-messaging-hosts/org.omarchy.zen_auto_style.json
```

Trigger a manual reload:

```bash
touch ~/.cache/zen-auto-style/reload
```

Verify the rendered theme file exists:

```bash
ls ~/.local/state/omarchy/current/theme/custom-zen.css
```

## Uninstall

Remove the extension in Zen, then run:

```bash
./uninstall.sh
```

The uninstall script removes the native host, Omarchy hook, managed browser
files, and the exact import/preference blocks added by the installer. CSS
outside those blocks is preserved. The Omarchy template is removed only if it
still matches the version shipped by this repository.

## Credits

Created by [gstrand99](https://github.com/gstrand99/zen-auto-style). Omarchy
4.x compatibility, dynamic path detection, and installer hardening contributed
by the community.

## License

Zen Auto Style is available under the [MIT License](LICENSE).
