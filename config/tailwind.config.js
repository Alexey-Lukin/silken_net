/** @type {import('tailwindcss').Config} */
module.exports = {
  darkMode: "class",
  content: [
    "./app/views/**/*.{rb,erb,html}",
    "./app/javascript/**/*.js",
    "./app/helpers/**/*.rb",
    "./app/assets/stylesheets/**/*.css",
  ],
  theme: {
    extend: {
      colors: {
        /* ── Gaia Design System: Semantic Surface / Text / Primary ── */
        "gaia-surface":        "var(--color-gaia-surface)",
        "gaia-surface-alt":    "var(--color-gaia-surface-alt)",
        "gaia-text":           "var(--color-gaia-text)",
        "gaia-text-muted":     "var(--color-gaia-text-muted)",
        "gaia-primary":        "var(--color-gaia-primary)",
        "gaia-primary-hover":  "var(--color-gaia-primary-hover)",
        "gaia-border":         "var(--color-gaia-border)",

        /* ── Status Colors (dynamic light/dark via CSS vars) ── */
        "status-danger":       "var(--color-status-danger)",
        "status-danger-text":  "var(--color-status-danger-text)",
        "status-danger-accent":"var(--color-status-danger-accent)",
        "status-warning":      "var(--color-status-warning)",
        "status-warning-text": "var(--color-status-warning-text)",
        "status-info":         "var(--color-status-info)",
        "status-info-text":    "var(--color-status-info-text)",
        "status-success":      "var(--color-status-success)",
        "status-success-text": "var(--color-status-success-text)",
        "status-active":       "var(--color-status-active)",
        "status-active-text":  "var(--color-status-active-text)",
        "status-neutral":      "var(--color-status-neutral)",
        "status-neutral-text": "var(--color-status-neutral-text)",

        /* ── Blockchain Token Colors ── */
        "token-carbon":        "var(--color-token-carbon)",
        "token-forest":        "var(--color-token-forest)",

        /* ── Form Input Colors ── */
        "gaia-input-bg":       "var(--color-gaia-input-bg)",
        "gaia-input-border":   "var(--color-gaia-input-border)",
        "gaia-input-text":     "var(--color-gaia-input-text)",
        "gaia-label":          "var(--color-gaia-label)",
      },
      fontFamily: {
        mono: [
          "JetBrains Mono", "Fira Code", "SF Mono", "Cascadia Code",
          "ui-monospace", "SFMono-Regular", "Menlo", "Monaco",
          "Consolas", "Liberation Mono", "Courier New", "monospace",
        ],
        sans: [
          "Inter", "system-ui", "-apple-system", "BlinkMacSystemFont",
          "Segoe UI", "Roboto", "Helvetica Neue", "Arial",
          "Noto Sans", "sans-serif",
        ],
      },
      fontSize: {
        "2xs": ["0.625rem", { lineHeight: "0.875rem" }],  /* 10px */
        "3xs": ["0.5rem",   { lineHeight: "0.75rem" }],   /*  8px */
      },
    },
  },
  plugins: [],
}
