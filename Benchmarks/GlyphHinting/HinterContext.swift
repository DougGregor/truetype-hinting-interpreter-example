import SwiftTrueTypeInterpreter

// MARK: - Phantom point count

private let kPrivatePhantomCount = 8

// MARK: - Zone storage

/// Allocates an `fnt_ElementType` with parallel point/contour arrays, zero-initialized.
private func makeElement(pointCapacity: Int, contourCapacity: Int) -> fnt_ElementType {
  var element = fnt_ElementType()
  element.x = .init(repeating: 0, count: pointCapacity)
  element.y = .init(repeating: 0, count: pointCapacity)
  element.ox = .init(repeating: 0, count: pointCapacity)
  element.oy = .init(repeating: 0, count: pointCapacity)
  element.oox = .init(repeating: 0, count: pointCapacity)
  element.ooy = .init(repeating: 0, count: pointCapacity)
  element.onCurve = .init(repeating: 0, count: pointCapacity)
  element.f = .init(repeating: 0, count: pointCapacity)
  element.sp = .init(repeating: 0, count: contourCapacity)
  element.ep = .init(repeating: 0, count: contourCapacity)
  element.maxPointCount = Int32(pointCapacity)
  element.maxContourCount = Int32(contourCapacity)
  return element
}

// MARK: - HinterContext

struct HinterContext: ~Copyable {
  let interpreter: SwiftTrueTypeInterpreter
  let unitsPerEm: Int16

  private var twilight: fnt_ElementType
  private var glyph: fnt_ElementType
  /// The parameter block the interpreter exports after each program.
  private(set) var parBlock: fnt_ParameterBlock = .init()

  init(
    tables: borrowing FontTables,
    pointSize: Int32
  ) throws {
    let maxp = tables.maxp
    self.unitsPerEm = tables.head.unitsPerEm
    self.interpreter = SwiftTrueTypeInterpreter(maxp: maxp, cvtCount: UInt16(tables.cvt.count))

    let glyphPoints = max(Int(maxp.maxPoints), Int(maxp.maxCompositePoints)) + kPrivatePhantomCount
    let glyphContours = max(Int(maxp.maxContours), Int(maxp.maxCompositeContours))
    let twilightPoints = Int(maxp.maxTwilightPoints)
    self.twilight = makeElement(pointCapacity: max(twilightPoints, 1), contourCapacity: 1)
    self.glyph = makeElement(pointCapacity: max(glyphPoints, 1), contourCapacity: max(glyphContours, 1))

    // CVT — convert FUnit Int16 to F26Dot6 (shift-left by fractionBits).
    if !tables.cvt.isEmpty {
      var cvt32 = UniqueArray<Int32>(minimumCapacity: tables.cvt.count)
      for i in 0..<tables.cvt.count { cvt32.append(Int32(tables.cvt[i]) << 6) }
      interpreter.setCVT(cvt32.span)
    }

    // Scale: `stretch` is F16Dot16 representation of pixels-per-em, so scaling an
    // FUnit by it and dividing by unitsPerEm produces an F26Dot6 pixel coordinate.
    let stretch = pointSize << 16
    interpreter.setScaleFactors(
      xStretch: stretch,
      yStretch: stretch,
      unitsPerEm: tables.head.unitsPerEm,
      pointSize: pointSize,
      cvtScale: stretch,
      isRotated: false,
      isStretched: false
    )

    // Run fpgm; then run prep with fpgm still in scope (prep may CALL fpgm functions).
    try interpreter.runProgram(
      fpgm: tables.fpgm.span, prep: Span<UInt8>(), glyf: Span<UInt8>(),
      unscaledOutlineIsWrong: false,
      parBlock: &parBlock
    )
    try interpreter.runProgram(
      fpgm: tables.fpgm.span, prep: tables.prep.span, glyf: Span<UInt8>(),
      twilightZone: &twilight,
      unscaledOutlineIsWrong: false,
      parBlock: &parBlock
    )
  }

  /// Populates the glyph zone with `g` (scaled by `pointSize`) and runs its bytecode.
  mutating func hint(
    _ g: borrowing ParsedGlyph,
    tables: borrowing FontTables,
    pointSize: Int32,
    advanceWidth: UInt16,
    leftSideBearing: Int16
  ) throws {
    Self.populate(
      &glyph, with: g, unitsPerEm: unitsPerEm, pointSize: pointSize,
      advanceWidth: advanceWidth, leftSideBearing: leftSideBearing)

    // Run the glyph bytecode. fpgm/prep are passed too so CALL/LOOPCALL
    // to functions defined in those programs can dereference their bytecode.
    try interpreter.runProgram(
      fpgm: tables.fpgm.span, prep: tables.prep.span, glyf: g.instructions.span,
      twilightZone: &twilight,
      glyphZone: &glyph,
      unscaledOutlineIsWrong: false,
      parBlock: &parBlock
    )
  }

  /// Writes `g`'s outline (scaled by `pointSize`) and phantom points into `elt`.
  ///
  /// Taking the element `inout` makes one exclusive access for the whole fill, so each array is
  /// written through a `MutableSpan` without per-write exclusivity checks.
  private static func populate(
    _ elt: inout fnt_ElementType,
    with g: borrowing ParsedGlyph,
    unitsPerEm: Int16,
    pointSize: Int32,
    advanceWidth: UInt16,
    leftSideBearing: Int16
  ) {
    let n = g.xCoords.count
    let phantomCount = kPrivatePhantomCount
    let totalPoints = n + phantomCount
    precondition(totalPoints <= Int(elt.maxPointCount), "glyph exceeds preallocated capacity")
    precondition(g.numContours <= Int(elt.maxContourCount), "contours exceed preallocated capacity")

    // Scale: F26Dot6 = fUnit * pointSize * 64 / unitsPerEm
    let upem = Int32(unitsPerEm)
    let pp64 = pointSize * 64
    @inline(__always) func scale(_ v: Int16) -> Int32 {
      // Round half-to-even style isn't critical for benchmark inputs.
      let prod = Int32(v) * pp64
      return prod / upem
    }

    // Phantom points (LSB, RSB, TSB, BSB), in FUnits.
    let lsb = leftSideBearing
    let rsb = Int16(truncatingIfNeeded: Int32(leftSideBearing) + Int32(advanceWidth))
    // Vertical phantoms (no vmtx parsed) → 0/0; common when fonts only use horizontal phantoms.
    let outlinePhantoms: [8 of (Int16, Int16)] = [
      (lsb, 0),
      (rsb, 0),
      (0, 0),
      (0, 0),
      // Private phantoms 4-7 (also typically zeroed when not used)
      (0, 0), (0, 0), (0, 0), (0, 0),
    ]

    // Populate point arrays — outline points first, then phantoms.
    do {
      var oox = elt.oox.mutableSpan
      var ooy = elt.ooy.mutableSpan
      var ox = elt.ox.mutableSpan
      var oy = elt.oy.mutableSpan
      var x = elt.x.mutableSpan
      var y = elt.y.mutableSpan
      var onCurve = elt.onCurve.mutableSpan
      var f = elt.f.mutableSpan
      for i in 0..<n {
        let oxx = g.xCoords[i]
        let oyy = g.yCoords[i]
        let sx = scale(oxx)
        let sy = scale(oyy)
        oox[i] = oxx
        ooy[i] = oyy
        ox[i] = sx
        oy[i] = sy
        x[i] = sx
        y[i] = sy
        onCurve[i] = g.onCurveFlags[i] ? 1 : 0
        f[i] = 0
      }
      for j in 0..<phantomCount {
        let i = n + j
        let (px, py) = outlinePhantoms[j]
        let sx = scale(px)
        let sy = scale(py)
        oox[i] = px
        ooy[i] = py
        ox[i] = sx
        oy[i] = sy
        x[i] = sx
        y[i] = sy
        onCurve[i] = 0
        f[i] = 0
      }
    }

    // Contour endpoints (sp/ep): a contour `c` covers points (endPts[c-1]+1 ... endPts[c]).
    do {
      var sp = elt.sp.mutableSpan
      var ep = elt.ep.mutableSpan
      var prev: Int = -1
      for c in 0..<g.numContours {
        let last = Int(g.endPts[c])
        sp[c] = UInt16(prev + 1)
        ep[c] = UInt16(last)
        prev = last
      }
    }

    elt.pointCount = Int32(n)
    elt.contourCount = Int32(g.numContours)
  }
}
