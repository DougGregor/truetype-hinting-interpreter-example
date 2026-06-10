import CoreText
import Foundation
import SwiftTrueTypeInterpreter

// MARK: - TrueType table tags

private let kTagHead: CTFontTableTag = 0x6865_6164  // 'head'
private let kTagMaxp: CTFontTableTag = 0x6D61_7870  // 'maxp'
private let kTagFpgm: CTFontTableTag = 0x6670_676D  // 'fpgm'
private let kTagPrep: CTFontTableTag = 0x7072_6570  // 'prep'
private let kTagCvt: CTFontTableTag = 0x6376_7420   // 'cvt '
private let kTagLoca: CTFontTableTag = 0x6C6F_6361  // 'loca'
private let kTagGlyf: CTFontTableTag = 0x676C_7966  // 'glyf'
private let kTagHhea: CTFontTableTag = 0x6868_6561  // 'hhea'
private let kTagHmtx: CTFontTableTag = 0x686D_7478  // 'hmtx'

// MARK: - Tables

struct HeadTable {
  let unitsPerEm: Int16
  let indexToLocFormat: Int16  // 0 = short (uint16 *2), 1 = long (uint32)
}

struct HheaTable {
  let numberOfHMetrics: UInt16
}

struct LongHorMetric {
  let advanceWidth: UInt16
  let leftSideBearing: Int16
}

struct FontTables: ~Copyable, @unchecked Sendable {
  let head: HeadTable
  let maxp: sfntMaxProfileTable
  let hhea: HheaTable
  let cvt: [Int16]
  let fpgm: [UInt8]
  let prep: [UInt8]
  let glyf: [UInt8]
  let loca: [UInt32]   // glyph offsets into `glyf`, length numGlyphs+1
  let hmtx: [LongHorMetric]

  static func load(fontName: String) -> FontTables {
    let font = CTFontCreateWithName(fontName as CFString, 12.0, nil)
    // `CTFontCreateWithName` silently falls back to a substitute font if the requested
    // name doesn't match anything installed (e.g. requesting a display-style name like
    // "STHeiti Medium" returns Helvetica). Validate that the resolved PostScript or
    // family name matches the request before the caller benches the wrong workload.
    let resolvedPS = CTFontCopyPostScriptName(font) as String
    let resolvedFamily = CTFontCopyFamilyName(font) as String
    guard resolvedPS == fontName || resolvedFamily == fontName else {
      fatalError("""
        font lookup for `\(fontName)` resolved to `\(resolvedPS)` (family `\(resolvedFamily)`) \
        — CT fell back to a substitute. Pass a PostScript or family name that matches an \
        installed font, or set `BENCHMARK_FONT_PATH` to a non-installed font file.
        """)
    }
    return load(ctFont: font)
  }

  /// Loads the first font from a TrueType / OpenType / TrueType Collection file at `path`.
  /// Used for fonts that aren't installed system-wide (e.g. test corpora).
  static func load(path: String) -> FontTables {
    let url = URL(fileURLWithPath: path) as CFURL
    guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url) as? [CTFontDescriptor],
          let descriptor = descriptors.first
    else {
      fatalError("no font descriptors at \(path)")
    }
    let font = CTFontCreateWithFontDescriptor(descriptor, 12.0, nil)
    return load(ctFont: font)
  }

  static func load(ctFont: CTFont) -> FontTables {
    func bytes(_ tag: CTFontTableTag) -> [UInt8]? {
      guard let cfdata = CTFontCopyTable(ctFont, tag, []) else { return nil }
      let length = CFDataGetLength(cfdata)
      guard length > 0 else { return [] }
      var out = [UInt8](repeating: 0, count: length)
      // SAFETY: CFDataGetBytes copies up to `length` bytes into `buf.baseAddress`,
      // and `out` was allocated with exactly that count above; the buffer lives only
      // for the duration of the closure, scoped by withUnsafeMutableBufferPointer.
      unsafe out.withUnsafeMutableBufferPointer { buf in
        unsafe CFDataGetBytes(cfdata, CFRange(location: 0, length: length), buf.baseAddress)
      }
      return out
    }
    guard let headBytes = bytes(kTagHead) else { fatalError("font has no `head` table") }
    guard let maxpBytes = bytes(kTagMaxp) else { fatalError("font has no `maxp` table") }
    guard let hheaBytes = bytes(kTagHhea) else { fatalError("font has no `hhea` table") }
    guard let locaBytes = bytes(kTagLoca) else { fatalError("font has no `loca` table — not a TrueType outline font?") }
    guard let glyfBytes = bytes(kTagGlyf) else { fatalError("font has no `glyf` table — not a TrueType outline font?") }
    guard let hmtxBytes = bytes(kTagHmtx) else { fatalError("font has no `hmtx` table") }
    let cvtBytes = bytes(kTagCvt) ?? []
    let fpgmBytes = bytes(kTagFpgm) ?? []
    let prepBytes = bytes(kTagPrep) ?? []

    let head = parseHead(headBytes)
    let maxp = parseMaxp(maxpBytes)
    let hhea = parseHhea(hheaBytes)
    let cvt = parseCvt(cvtBytes)
    let loca = parseLoca(locaBytes, numGlyphs: maxp.numGlyphs, isLong: head.indexToLocFormat == 1)
    let hmtx = parseHmtx(hmtxBytes, numHMetrics: hhea.numberOfHMetrics, numGlyphs: maxp.numGlyphs)
    return FontTables(
      head: head,
      maxp: maxp,
      hhea: hhea,
      cvt: cvt,
      fpgm: fpgmBytes,
      prep: prepBytes,
      glyf: glyfBytes,
      loca: loca,
      hmtx: hmtx
    )
  }
}

/// Reference-typed holder so multiple stored escaping closures can share access
/// to a `~Copyable` `FontTables`.
final class FontTablesBox: @unchecked Sendable {
  let tables: FontTables
  init(_ tables: consuming FontTables) {
    self.tables = tables
  }
}

// MARK: - Big-endian byte reader

struct ByteReader {
  let bytes: [UInt8]
  var offset: Int = 0

  mutating func u16() -> UInt16 {
    let v = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    offset += 2
    return v
  }
  mutating func i16() -> Int16 { Int16(bitPattern: u16()) }
  mutating func u32() -> UInt32 {
    let v = (UInt32(bytes[offset]) << 24)
      | (UInt32(bytes[offset + 1]) << 16)
      | (UInt32(bytes[offset + 2]) << 8)
      | UInt32(bytes[offset + 3])
    offset += 4
    return v
  }
  mutating func i32() -> Int32 { Int32(bitPattern: u32()) }
  mutating func u8() -> UInt8 {
    let v = bytes[offset]
    offset += 1
    return v
  }
  mutating func i8() -> Int8 { Int8(bitPattern: u8()) }
  mutating func skip(_ n: Int) { offset += n }
}

// MARK: - Table parsers

private func parseHead(_ bytes: [UInt8]) -> HeadTable {
  var r = ByteReader(bytes: bytes)
  r.skip(18)   // version, fontRevision, checksumAdjustment, magicNumber, flags
  let unitsPerEm = r.i16()
  r.skip(30)   // created, modified, xMin..yMax, macStyle, lowestRecPPEM, fontDirectionHint
  let indexToLocFormat = r.i16()
  return HeadTable(unitsPerEm: unitsPerEm, indexToLocFormat: indexToLocFormat)
}

private func parseMaxp(_ bytes: [UInt8]) -> sfntMaxProfileTable {
  var r = ByteReader(bytes: bytes)
  let version = r.i32()
  let numGlyphs = r.u16()
  // Only v1.0 has the full table; v0.5 only has version+numGlyphs.
  guard version == 0x0001_0000 else {
    return sfntMaxProfileTable(version: version, numGlyphs: numGlyphs)
  }
  let maxPoints = r.u16()
  let maxContours = r.u16()
  let maxCompositePoints = r.u16()
  let maxCompositeContours = r.u16()
  let maxZones = r.u16()
  let maxTwilightPoints = r.u16()
  let maxStorage = r.u16()
  let maxFunctionDefs = r.u16()
  let maxInstructionDefs = r.u16()
  let maxStackElements = r.u16()
  let maxSizeOfInstructions = r.u16()
  let maxComponentElements = r.u16()
  let maxComponentDepth = r.u16()
  return sfntMaxProfileTable(
    version: version,
    numGlyphs: numGlyphs,
    maxPoints: maxPoints,
    maxContours: maxContours,
    maxCompositePoints: maxCompositePoints,
    maxCompositeContours: maxCompositeContours,
    maxElements: max(maxZones, 2),
    maxTwilightPoints: maxTwilightPoints,
    maxStorage: maxStorage,
    maxFunctionDefs: maxFunctionDefs,
    maxInstructionDefs: maxInstructionDefs,
    maxStackElements: maxStackElements,
    maxSizeOfInstructions: maxSizeOfInstructions,
    maxComponentElements: maxComponentElements,
    maxComponentDepth: maxComponentDepth
  )
}

private func parseHhea(_ bytes: [UInt8]) -> HheaTable {
  var r = ByteReader(bytes: bytes)
  r.skip(34)   // version through metricDataFormat
  let numberOfHMetrics = r.u16()
  return HheaTable(numberOfHMetrics: numberOfHMetrics)
}

private func parseCvt(_ bytes: [UInt8]) -> [Int16] {
  var r = ByteReader(bytes: bytes)
  let count = bytes.count / 2
  var out: [Int16] = []
  out.reserveCapacity(count)
  for _ in 0..<count { out.append(r.i16()) }
  return out
}

private func parseLoca(_ bytes: [UInt8], numGlyphs: UInt16, isLong: Bool) -> [UInt32] {
  var r = ByteReader(bytes: bytes)
  let count = Int(numGlyphs) + 1
  var out: [UInt32] = []
  out.reserveCapacity(count)
  if isLong {
    for _ in 0..<count { out.append(r.u32()) }
  } else {
    for _ in 0..<count { out.append(UInt32(r.u16()) * 2) }
  }
  return out
}

private func parseHmtx(_ bytes: [UInt8], numHMetrics: UInt16, numGlyphs: UInt16) -> [LongHorMetric] {
  var r = ByteReader(bytes: bytes)
  var out: [LongHorMetric] = []
  out.reserveCapacity(Int(numGlyphs))
  var lastAdvance: UInt16 = 0
  for _ in 0..<numHMetrics {
    let aw = r.u16()
    let lsb = r.i16()
    out.append(LongHorMetric(advanceWidth: aw, leftSideBearing: lsb))
    lastAdvance = aw
  }
  let trailing = Int(numGlyphs) - Int(numHMetrics)
  for _ in 0..<max(0, trailing) {
    let lsb = r.i16()
    out.append(LongHorMetric(advanceWidth: lastAdvance, leftSideBearing: lsb))
  }
  return out
}
