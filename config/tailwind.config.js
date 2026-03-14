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
