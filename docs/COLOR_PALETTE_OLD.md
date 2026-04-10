# Tempo for Claude — Color Palette

Two palettes exist in the codebase:

- **TempoTheme** (`Tempo macOS/TempoTheme.swift`) — active design system for the macOS menu bar app (graphite dark + electric violet)
- **Shared/Theme** (`Shared/Theme.swift`) — legacy Claude terracotta palette, kept for shared targets

---

## TempoTheme (primary)

### Backgrounds

| Token | Hex | Preview | Notes |
|---|---|---|---|
| `background` | `#19191C` | ██ | Deepest background |
| `surface` | `#222226` | ██ | Elevated surface |
| `card` | `#26262B` | ██ | Card / panel layer |
| `progressTrack` | `#333339` | ██ | Ring/progress track background |

### Accent — Electric Violet

| Token | Hex | Preview | Notes |
|---|---|---|---|
| `accent` | `#7B4DED` | ██ | Primary brand accent |
| `accentLight` | `#9B76F9` | ██ | Hover / highlight states |
| `accentMuted` | `#7B4DED` @ 15% | ██ | Subtle accent fills |

### Text

| Token | Hex | Preview | Notes |
|---|---|---|---|
| `textPrimary` | `#EEEEEF` | ██ | Body, headings |
| `textSecondary` | `#888892` | ██ | Supporting labels |
| `textTertiary` | `#5F5F68` | ██ | Dim / disabled |

### Semantic / Status

| Token | Hex | Preview | Notes |
|---|---|---|---|
| `success` | `#4CC28D` | ██ | Operational, low usage |
| `warning` | `#F9BB3B` | ██ | Degraded, medium usage |
| `critical` | `#EF5363` | ██ | Major outage, high usage |
| `info` | `#4D99E0` | ██ | Informational |
| `destructive` | `#EF5363` | ██ | Alias of `critical` |

---

## Shared / Legacy (terracotta)

Used by iOS and watchOS targets. Not used in the macOS Tempo UI.

### Accent — Claude Terracotta

| Token | Hex | Notes |
|---|---|---|
| `claudeAccent` | `#C15F3C` | Primary brand accent |
| `claudeAccentDark` | `#A14A2F` | Hover / pressed |
| `claudeAccentLight` | `#D4916A` | Lighter warm accent |

### Backgrounds

| Token | Hex | Notes |
|---|---|---|
| `claudeBgDeep` | `#1A1815` | Deepest background |
| `claudeBgElevated` | `#201D18` | Sidebars, cards |
| `claudeBgSurface` | `#2A251D` | Activity bar, inactive tabs |
| `claudeBorder` | `#3A352B` | Dividers and borders |

### Text

| Token | Hex | Notes |
|---|---|---|
| `claudeTextPrimary` | `#E8E6E3` | Warm off-white |
| `claudeTextSecondary` | `#9A9389` | Muted |
| `claudeTextTertiary` | `#6A6158` | Dim / disabled |

### Status

| Token | Hex | Notes |
|---|---|---|
| `claudeGreen` | `#4CAF50` | Success / low utilization |
| `claudeYellow` | `#F3DF31` | Warning / medium utilization |
| `claudeRed` | `#FF6B6B` | Critical / high utilization |
| `claudeBlue` | `#42A5F5` | Informational / 7d ring |

### Ring Tracks

| Token | Value | Notes |
|---|---|---|
| `claudeRingTrack` | `white @ 15%` | Outer ring track |
| `claudeRingTrackInner` | `white @ 10%` | Inner ring track |
