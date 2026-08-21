:root {
  --custom-zen-color-scheme: {{ mode }};
  --custom-zen-bg: {{ background }};
  --custom-zen-fg: {{ foreground }};
  --custom-zen-accent: {{ accent }};

  --custom-zen-surface-0: {{ background }};
  --custom-zen-surface-1: {{ color0 }};
  --custom-zen-surface-2: {{ color8 }};

  --custom-zen-border: color-mix(in srgb, {{ background }} 80%, {{ foreground }});
  --custom-zen-panel: color-mix(in srgb, {{ background }} 88%, {{ foreground }});

  --custom-zen-accent-hover: color-mix(in srgb, {{ accent }} 85%, white);
  --custom-zen-accent-active: color-mix(in srgb, {{ accent }} 85%, black);

  --custom-zen-red: {{ color1 }};
  --custom-zen-green: {{ color2 }};
  --custom-zen-yellow: {{ color3 }};
  --custom-zen-blue: {{ color4 }};
  --custom-zen-pink: {{ color5 }};
  --custom-zen-cyan: {{ color6 }};

  --custom-zen-orange: color-mix(in srgb, {{ color1 }} 50%, {{ color3 }} 50%);
  --custom-zen-purple: color-mix(in srgb, {{ color4 }} 50%, {{ color5 }} 50%);

  --custom-zen-selection-bg: {{ selection_background }};
  --custom-zen-selection-fg: {{ selection_foreground }};

  --custom-zen-fg-muted: rgba({{ foreground_rgb }}, 0.7);
  --custom-zen-fg-faint: rgba({{ foreground_rgb }}, 0.55);
}
