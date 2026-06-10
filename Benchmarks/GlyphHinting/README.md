# GlyphHinting Benchmark

Measures wall-clock and CPU cost of running the SwiftTrueTypeInterpreter against real glyph bytecode at multiple pixel sizes. Used to verify that interpreter changes don't regress hot paths and to quantify wins from optimization work.

## Running

```sh
swift package --allow-writing-to-package-directory benchmark
```

Behind the scenes this invokes the [package-benchmark](https://github.com/ordo-one/package-benchmark) plugin, which compiles the `GlyphHinting` executable target in release configuration, executes each registered benchmark for `maxDuration` (3s) or `maxIterations` (1M), and prints a percentile table to stdout.

To run a single benchmark:

```sh
swift package --allow-writing-to-package-directory benchmark --filter "hint-Helvetica-24ppem"
```

To compare two revisions (e.g. before and after a change):

```sh
git checkout <baseline-sha>
swift package --allow-writing-to-package-directory benchmark baseline update baseline
git checkout <candidate-sha>
swift package --allow-writing-to-package-directory benchmark baseline compare baseline
```

The `compare` output highlights percentile-by-percentile deltas with statistical significance flags.

## Configuration

| Knob | Default | Effect |
| --- | --- | --- |
| `BENCHMARK_FONT_NAME` env var | unset | Replace the default workload with a single system-installed font, looked up by **PostScript name** (preferred) or family name. CT silently falls back to a substitute when neither matches; the loader validates the resolved name and traps if a fallback occurred. |
| `BENCHMARK_FONT_PATH` env var | unset | Replace the default workload with a single TrueType / OpenType / TrueType Collection file at the given path (loaded via `CTFontManagerCreateFontDescriptorsFromURL`). For `.ttc` collections the first descriptor is used. Takes precedence over `BENCHMARK_FONT_NAME`. |
| `GLYPH_LIMIT` env var | `256` | Maximum number of hintable glyphs collected per font. |
| `Benchmark.defaultConfiguration` | 3 warmup iterations, 3s max duration, 1M max iterations, metrics: wallClock / cpuTotal / throughput | Edit `GlyphHintingBenchmarks.swift` to change. |

## Workload

Three fonts are exercised by default—one Latin sans, one Latin monospaced, one CJK with rich bytecode hinting:

| Display label | PostScript lookup | File |
| --- | --- | --- |
| `Helvetica` | `Helvetica` | `/System/Library/Fonts/Helvetica.ttc` |
| `Courier New` | `Courier New` (family) → `CourierNewPSMT` | `/System/Library/Fonts/Supplemental/Courier New.ttf` |
| `STHeiti SC Medium` | `STHeitiSC-Medium` | `/System/Library/Fonts/STHeiti Medium.ttc` |

All three ship with macOS. `FontTables.load(fontName:)` validates that the resolved PostScript or family name matches the requested string; if `CTFontCreateWithName` falls back to a substitute (e.g. because the font isn't installed, or because a display-style name was used instead of a PostScript name), the loader traps with a clear error.

To benchmark other fonts, point `BENCHMARK_FONT_PATH` at a TrueType file:

```sh
BENCHMARK_FONT_PATH=/path/to/your/font.ttc swift package --allow-writing-to-package-directory benchmark
```

## What gets measured

Each `hint-*` benchmark, per iteration:

1. Constructs a fresh `HinterContext(tables:pointSize:)` (loads CVT, runs `prep` if present, sets up phantom points).
2. Calls `ctx.hint(...)` for every glyph in the filtered list.

Reported metrics:
- `.wallClock`: real time per iteration
- `.cpuTotal`: user + system CPU time per iteration
- `.throughput`: iterations per second

Percentiles surfaced by package-benchmark: p0 (min), p25, p50, p75, p90, p99, p100 (max).
