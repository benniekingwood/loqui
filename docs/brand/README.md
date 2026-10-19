# Loqui brand

The mark is the **Cursor Wave**: four sound bars that step up and resolve into
a text cursor. Speech goes in, text appears at the caret. Loqui uses the
**Spectrum** colorway, where each bar has its own color.

<img src="loqui-icon.png" width="128" height="128" alt="Loqui app icon">

## Palette

| Role | Color |
|---|---|
| Ground | `#0F1419` |
| Bar 1, coral | `#FF6B5B` |
| Bar 2, amber | `#FFB547` |
| Bar 3, mint | `#3DDC97` |
| Bar 4, sky | `#5AC8FA` |
| Cursor and wordmark | `#FFFFFF` |

The wordmark is lowercase `loqui` set in JetBrains Mono Bold.

## Assets

| Asset | Source |
|---|---|
| App icon, `Loqui/AppIcon.icns` | `scripts/generate-brand-assets.swift` |
| README icon, `docs/brand/loqui-icon.png` | `scripts/generate-brand-assets.swift` |
| Menu bar icon | Drawn in code by `MenuBarGlyph.swift` |

The menu bar icon is a one-color template image, so macOS tints it for light
and dark menu bars. Idle shows the bars and cursor. Recording raises the bars
and turns the cursor into a dot.

Regenerate the icon files after changing the mark:

```sh
swift scripts/generate-brand-assets.swift
```
