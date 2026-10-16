// Parses a single TrueType simple glyph from the `glyf` table.
// Composite glyphs are returned as `.composite` and are not benchmarked.

struct ParsedGlyph: Sendable {
  /// Number of contours (always > 0 here).
  let numContours: Int
  let xMin: Int16
  let yMin: Int16
  let xMax: Int16
  let yMax: Int16
  /// Last point index per contour; `pointCount = endPts.last + 1`.
  let endPts: [UInt16]
  /// Glyph bytecode (the slice handed to `runProgram(.glyf, ...)`).
  let instructions: [UInt8]
  let xCoords: [Int16]
  let yCoords: [Int16]
  let onCurveFlags: [Bool]
}

enum GlyphParseResult {
  case empty
  case simple(ParsedGlyph)
  case composite
}

func parseGlyph(glyf: Span<UInt8>, offset: UInt32, length: UInt32) -> GlyphParseResult {
  guard length > 0 else { return .empty }
  let start = Int(offset)
  let end = start + Int(length)
  var r = ByteReader(bytes: glyf.extracting(start..<end))
  let numContoursSigned = r.i16()
  if numContoursSigned < 0 { return .composite }
  let numContours = Int(numContoursSigned)
  let xMin = r.i16()
  let yMin = r.i16()
  let xMax = r.i16()
  let yMax = r.i16()

  if numContours == 0 {
    // Header-only entry, skip.
    return .empty
  }

  var endPts: [UInt16] = []
  endPts.reserveCapacity(numContours)
  for _ in 0..<numContours { endPts.append(r.u16()) }

  let instructionLength = Int(r.u16())
  var instructions: [UInt8] = []
  instructions.reserveCapacity(instructionLength)
  for _ in 0..<instructionLength { instructions.append(r.u8()) }

  let pointCount = Int(endPts.last!) + 1

  // Flags (with REPEAT_FLAG support)
  var flags: [UInt8] = []
  flags.reserveCapacity(pointCount)
  while flags.count < pointCount {
    let f = r.u8()
    flags.append(f)
    if f & 0x08 != 0 {  // REPEAT_FLAG
      let n = Int(r.u8())
      for _ in 0..<n { flags.append(f) }
    }
  }

  var xCoords: [Int16] = []
  xCoords.reserveCapacity(pointCount)
  var x: Int16 = 0
  for f in flags {
    if f & 0x02 != 0 {  // X_SHORT_VECTOR (1 byte)
      let v = Int16(r.u8())
      let positive = f & 0x10 != 0
      x &+= positive ? v : -v
    } else if f & 0x10 == 0 {  // not X_IS_SAME — full int16 delta
      let dx = r.i16()
      x &+= dx
    }
    xCoords.append(x)
  }

  var yCoords: [Int16] = []
  yCoords.reserveCapacity(pointCount)
  var y: Int16 = 0
  for f in flags {
    if f & 0x04 != 0 {  // Y_SHORT_VECTOR
      let v = Int16(r.u8())
      let positive = f & 0x20 != 0
      y &+= positive ? v : -v
    } else if f & 0x20 == 0 {  // not Y_IS_SAME
      let dy = r.i16()
      y &+= dy
    }
    yCoords.append(y)
  }

  let onCurve = flags.map { $0 & 0x01 != 0 }
  return .simple(
    ParsedGlyph(
      numContours: numContours,
      xMin: xMin,
      yMin: yMin,
      xMax: xMax,
      yMax: yMax,
      endPts: endPts,
      instructions: instructions,
      xCoords: xCoords,
      yCoords: yCoords,
      onCurveFlags: onCurve
    )
  )
}
