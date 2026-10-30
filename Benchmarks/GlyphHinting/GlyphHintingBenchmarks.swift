import Benchmark
import Foundation
import SwiftTrueTypeInterpreter

private struct GlyphCase: Sendable {
  let parsed: ParsedGlyph
  let advance: UInt16
  let lsb: Int16
}

private func collectGlyphs(_ tables: borrowing FontTables, limit: Int) -> [GlyphCase] {
  var prepared: [GlyphCase] = []
  prepared.reserveCapacity(Int(tables.maxp.numGlyphs))
  for glyphIdx in 1..<Int(tables.maxp.numGlyphs) {
    let off = tables.loca[glyphIdx]
    let nextOff = tables.loca[glyphIdx + 1]
    guard nextOff > off else { continue }
    let len = nextOff - off
    if case .simple(let g) = parseGlyph(glyf: tables.glyf.span, offset: off, length: len),
      !g.instructions.isEmpty
    {
      let m = tables.hmtx[glyphIdx]
      prepared.append(GlyphCase(parsed: g, advance: m.advanceWidth, lsb: m.leftSideBearing))
    }
    if prepared.count >= limit { break }
  }
  return prepared
}

/// Filters out glyphs that throw when hinted at any of the target ppems. Real
/// fonts occasionally contain bytecode the interpreter can't (yet) handle — most
/// notably Helvetica's glyph 234 — and we don't want a single bad glyph to mask
/// the whole benchmark run.
private func filterHintable(
  _ all: [GlyphCase],
  tables: borrowing FontTables,
  ppems: [Int32]
) -> [GlyphCase] {
  var keep: [GlyphCase] = []
  keep.reserveCapacity(all.count)
  outer: for c in all {
    for ppem in ppems {
      guard var ctx = try? HinterContext(tables: tables, pointSize: ppem) else { return keep }
      do {
        try ctx.hint(c.parsed, tables: tables, pointSize: ppem, advanceWidth: c.advance, leftSideBearing: c.lsb)
      } catch {
        continue outer
      }
    }
    keep.append(c)
  }
  return keep
}

// MARK: - Entry point used by package-benchmark plugin

private enum FontSource {
  case systemName(String)
  case path(String)

  func load() -> FontTables {
    switch self {
    case .systemName(let name): FontTables.load(fontName: name)
    case .path(let path): FontTables.load(path: path)
    }
  }
}

let benchmarks: @Sendable () -> Void = {
  // Default workload: one Latin sans, one Latin monospaced, one CJK with rich
  // bytecode hinting — all three system-installed on macOS. To run a different
  // single workload, set BENCHMARK_FONT_PATH (file path to a TrueType / OpenType /
  // TrueType Collection) or BENCHMARK_FONT_NAME (PostScript or family name of an
  // installed font). Either override replaces the default trio (use exactly one).
  //
  // CJK note: STHeiti is one of the very few TrueType-flavored CJK families on
  // macOS that ships with rich `prep`/`fpgm` bytecode (most CJK fonts on macOS —
  // PingFang, Hiragino Sans GB, AppleSDGothicNeo — are CFF-flavored and have no
  // `glyf` table for the interpreter to operate on). The PostScript name
  // `STHeitiSC-Medium` resolves to a face inside `/System/Library/Fonts/STHeiti
  // Medium.ttc`; the display-style name "STHeiti Medium" silently falls back to
  // Helvetica because CT only matches PostScript / family names.
  let env = ProcessInfo.processInfo.environment
  let fonts: [(name: String, source: FontSource)] = {
    if let path = env["BENCHMARK_FONT_PATH"] {
      let displayName = (path as NSString).lastPathComponent
      return [(displayName, .path(path))]
    }
    if let name = env["BENCHMARK_FONT_NAME"] {
      return [(name, .systemName(name))]
    }
    return [
      ("Helvetica", .systemName("Helvetica")),
      ("Courier New", .systemName("Courier New")),
      ("STHeiti SC Medium", .systemName("STHeitiSC-Medium")),
    ]
  }()
  let limit = Int(env["GLYPH_LIMIT"].flatMap(Int.init) ?? 256)
  let ppems: [Int32] = [12, 24, 48]

  // SAFETY: `Benchmark.defaultConfiguration` is `nonisolated(unsafe)` because the
  // package-benchmark API treats it as a setup-time singleton. We assign once here
  // before any `Benchmark(...)` registration runs, so there are no concurrent reads.
  unsafe Benchmark.defaultConfiguration = Benchmark.Configuration(
    metrics: [.wallClock, .cpuTotal, .throughput],
    warmupIterations: 3,
    maxDuration: .seconds(3),
    maxIterations: 1_000_000
  )

  for (fontName, source) in fonts {
    let box = FontTablesBox(source.load())
    let allGlyphs = collectGlyphs(box.tables, limit: limit)
    let glyphsToHint = filterHintable(allGlyphs, tables: box.tables, ppems: ppems)

    for ppem in ppems {
      Benchmark("hint-\(fontName)-\(ppem)ppem") { benchmark in
        for _ in benchmark.scaledIterations {
          var ctx = try HinterContext(tables: box.tables, pointSize: ppem)
          for c in glyphsToHint {
            try ctx.hint(c.parsed, tables: box.tables, pointSize: ppem, advanceWidth: c.advance, leftSideBearing: c.lsb)
          }
          blackHole(ctx.parBlock)
        }
      }
    }

    Benchmark("setup-\(fontName)-12ppem") { benchmark in
      for _ in benchmark.scaledIterations {
        let ctx = try HinterContext(tables: box.tables, pointSize: 12)
        blackHole(ctx.parBlock)
      }
    }
  }
}
