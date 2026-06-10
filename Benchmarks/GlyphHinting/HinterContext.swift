import SwiftTrueTypeInterpreter

// MARK: - Phantom point count

private let kPrivatePhantomCount = 8

// MARK: - ZoneStorage

// SAFETY: Owns an `fnt_ElementType` allocation with parallel point/contour arrays.
// All allocations are paired with deinit deallocations. Pointer escapes only
// to interpreter `runProgram` calls scoped to the storage's lifetime.
@unsafe final class ZoneStorage {
  let element: UnsafeMutablePointer<fnt_ElementType>
  let pointCapacity: Int
  let contourCapacity: Int

  init(pointCapacity: Int, contourCapacity: Int) {
    // SAFETY: every `.allocate(capacity:)` below is paired with a `.deallocate()` in
    // `deinit`, gated on the same `pointCapacity > 0` / `contourCapacity > 0` condition
    // recorded into `self.{point,contour}Capacity` here. `.initialize(repeating:count:)`
    // touches exactly `count` elements of a buffer just allocated with that same
    // capacity. Stored properties of an `@unsafe` class require `unsafe` to write.
    unsafe self.pointCapacity = pointCapacity
    unsafe self.contourCapacity = contourCapacity
    let elt = UnsafeMutablePointer<fnt_ElementType>.allocate(capacity: 1)
    unsafe elt.initialize(to: fnt_ElementType())
    if pointCapacity > 0 {
      unsafe elt.pointee.x = .allocate(capacity: pointCapacity)
      unsafe elt.pointee.y = .allocate(capacity: pointCapacity)
      unsafe elt.pointee.ox = .allocate(capacity: pointCapacity)
      unsafe elt.pointee.oy = .allocate(capacity: pointCapacity)
      unsafe elt.pointee.oox = .allocate(capacity: pointCapacity)
      unsafe elt.pointee.ooy = .allocate(capacity: pointCapacity)
      unsafe elt.pointee.onCurve = .allocate(capacity: pointCapacity)
      unsafe elt.pointee.f = .allocate(capacity: pointCapacity)
      unsafe elt.pointee.x.initialize(repeating: 0, count: pointCapacity)
      unsafe elt.pointee.y.initialize(repeating: 0, count: pointCapacity)
      unsafe elt.pointee.ox.initialize(repeating: 0, count: pointCapacity)
      unsafe elt.pointee.oy.initialize(repeating: 0, count: pointCapacity)
      unsafe elt.pointee.oox.initialize(repeating: 0, count: pointCapacity)
      unsafe elt.pointee.ooy.initialize(repeating: 0, count: pointCapacity)
      unsafe elt.pointee.onCurve.initialize(repeating: 0, count: pointCapacity)
      unsafe elt.pointee.f.initialize(repeating: 0, count: pointCapacity)
    }
    if contourCapacity > 0 {
      unsafe elt.pointee.sp = .allocate(capacity: contourCapacity)
      unsafe elt.pointee.ep = .allocate(capacity: contourCapacity)
      unsafe elt.pointee.sp.initialize(repeating: 0, count: contourCapacity)
      unsafe elt.pointee.ep.initialize(repeating: 0, count: contourCapacity)
    }
    unsafe elt.pointee.maxPointCount = Int32(pointCapacity)
    unsafe elt.pointee.maxContourCount = Int32(contourCapacity)
    unsafe elt.pointee.pointCount = 0
    unsafe elt.pointee.contourCount = 0
    unsafe self.element = elt
  }

  deinit {
    // SAFETY: deallocates exactly the buffers `init` allocated, gated on the same
    // capacity conditions captured into `self.{point,contour}Capacity`. The element
    // itself was allocated unconditionally and is unconditionally deallocated last.
    if unsafe pointCapacity > 0 {
      unsafe element.pointee.x.deallocate()
      unsafe element.pointee.y.deallocate()
      unsafe element.pointee.ox.deallocate()
      unsafe element.pointee.oy.deallocate()
      unsafe element.pointee.oox.deallocate()
      unsafe element.pointee.ooy.deallocate()
      unsafe element.pointee.onCurve.deallocate()
      unsafe element.pointee.f.deallocate()
    }
    if unsafe contourCapacity > 0 {
      unsafe element.pointee.sp.deallocate()
      unsafe element.pointee.ep.deallocate()
    }
    unsafe element.deallocate()
  }
}

// MARK: - HinterContext

// SAFETY: encapsulates the `@unsafe ZoneStorage` allocations in a safe interface —
// pointer escapes go only into `interpreter.runProgram(...)` calls scoped to this
// object's lifetime, and the storage objects own their allocations and outlive
// every call we initiate.
@safe final class HinterContext {
  let interpreter: SwiftTrueTypeInterpreter
  let unitsPerEm: Int16

  // SAFETY: pointers held only for the duration of program runs initiated through
  // this object; the storage objects own their allocations and outlive every call.
  private let twilight: ZoneStorage
  private let glyph: ZoneStorage
  private var parBlock: fnt_ParameterBlock = .init()

  /// fpgm/prep bytecode arrays held to keep their `withUnsafeBufferPointer` slices
  /// stable across the run setup.
  private let fpgmBytes: [UInt8]
  private let prepBytes: [UInt8]

  init(
    tables: borrowing FontTables,
    pointSize: Int32
  ) throws {
    let maxp = tables.maxp
    self.unitsPerEm = tables.head.unitsPerEm
    self.fpgmBytes = tables.fpgm
    self.prepBytes = tables.prep
    self.interpreter = SwiftTrueTypeInterpreter(maxp: maxp, cvtCount: UInt16(tables.cvt.count))

    let glyphPoints = max(Int(maxp.maxPoints), Int(maxp.maxCompositePoints)) + kPrivatePhantomCount
    let glyphContours = max(Int(maxp.maxContours), Int(maxp.maxCompositeContours))
    let twilightPoints = Int(maxp.maxTwilightPoints)
    // SAFETY: `ZoneStorage` is `@unsafe`, so storing or constructing one requires the
    // `unsafe` keyword. Ownership is by `self`; both storages outlive every interpreter
    // call we initiate, and their deallocations run when `self` deinits.
    unsafe self.twilight = ZoneStorage(pointCapacity: max(twilightPoints, 1), contourCapacity: 1)
    unsafe self.glyph = ZoneStorage(pointCapacity: max(glyphPoints, 1), contourCapacity: max(glyphContours, 1))

    // CVT — convert FUnit Int16 to F26Dot6 (shift-left by fractionBits).
    if !tables.cvt.isEmpty {
      let cvt32 = tables.cvt.map { Int32($0) << 6 }
      // SAFETY: `buf` is valid for the closure scope; `setCVT` copies through the
      // pointer synchronously and does not retain it.
      unsafe cvt32.withUnsafeBufferPointer { buf in
        unsafe interpreter.setCVT(buf.baseAddress!, count: buf.count)
      }
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
    // SAFETY: `fpgmBuf`/`prepBuf` are valid only within their `withUnsafeBufferPointer`
    // closures; `runProgram` consumes the pointers synchronously and does not retain
    // them past the call. `twilight.element` is owned by `self` for the call duration.
    try unsafe fpgmBytes.withUnsafeBufferPointer { fpgmBuf in
      try unsafe interpreter.runProgram(
        fpgm: fpgmBuf.baseAddress, fpgmCount: Int32(fpgmBuf.count),
        prep: nil, prepCount: 0,
        glyf: nil, glyfCount: 0,
        twilightZone: nil, glyphZone: nil,
        unscaledOutlineIsWrong: false,
        parBlock: &parBlock
      )
      try unsafe prepBytes.withUnsafeBufferPointer { prepBuf in
        try unsafe interpreter.runProgram(
          fpgm: fpgmBuf.baseAddress, fpgmCount: Int32(fpgmBuf.count),
          prep: prepBuf.isEmpty ? nil : prepBuf.baseAddress,
          prepCount: Int32(prepBuf.count),
          glyf: nil, glyfCount: 0,
          twilightZone: unsafe twilight.element, glyphZone: nil,
          unscaledOutlineIsWrong: false,
          parBlock: &parBlock
        )
      }
    }
  }

  /// Populates the glyph zone with `g` (scaled by `pointSize`) and runs its bytecode.
  func hint(
    _ g: borrowing ParsedGlyph,
    pointSize: Int32,
    advanceWidth: UInt16,
    leftSideBearing: Int16
  ) throws {
    let n = g.xCoords.count
    let phantomCount = kPrivatePhantomCount
    let totalPoints = n + phantomCount
    // SAFETY: capacity reads on `glyph` (an `@unsafe ZoneStorage`) require `unsafe`.
    // The capacity values were set in `ZoneStorage.init` and are immutable thereafter.
    precondition(unsafe totalPoints <= glyph.pointCapacity, "glyph exceeds preallocated capacity")
    precondition(unsafe g.numContours <= glyph.contourCapacity, "contours exceed preallocated capacity")

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
    let outlinePhantoms: [(Int16, Int16)] = [
      (lsb, 0),
      (rsb, 0),
      (0, 0),
      (0, 0),
      // Private phantoms 4-7 (also typically zeroed when not used)
      (0, 0), (0, 0), (0, 0), (0, 0),
    ]

    // Populate point arrays — outline points first, then phantoms.
    // SAFETY for the writes below: each `elt.pointee.<field>` is a buffer of length
    // `pointCapacity` allocated and initialized in `ZoneStorage.init`. The two loops
    // together cover indices `0..<(n + phantomCount) == 0..<totalPoints`, and
    // `totalPoints <= glyph.pointCapacity` was asserted above. Reading `glyph.element`
    // on an `@unsafe` class also requires `unsafe`.
    let elt = unsafe glyph.element
    for i in 0..<n {
      let oxx = g.xCoords[i]
      let oyy = g.yCoords[i]
      let sx = scale(oxx)
      let sy = scale(oyy)
      unsafe elt.pointee.oox[i] = oxx
      unsafe elt.pointee.ooy[i] = oyy
      unsafe elt.pointee.ox[i] = sx
      unsafe elt.pointee.oy[i] = sy
      unsafe elt.pointee.x[i] = sx
      unsafe elt.pointee.y[i] = sy
      unsafe elt.pointee.onCurve[i] = g.onCurveFlags[i] ? 1 : 0
      unsafe elt.pointee.f[i] = 0
    }
    for j in 0..<phantomCount {
      let i = n + j
      let (px, py) = outlinePhantoms[j]
      let sx = scale(px)
      let sy = scale(py)
      unsafe elt.pointee.oox[i] = px
      unsafe elt.pointee.ooy[i] = py
      unsafe elt.pointee.ox[i] = sx
      unsafe elt.pointee.oy[i] = sy
      unsafe elt.pointee.x[i] = sx
      unsafe elt.pointee.y[i] = sy
      unsafe elt.pointee.onCurve[i] = 0
      unsafe elt.pointee.f[i] = 0
    }

    // Contour endpoints (sp/ep): a contour `c` covers points (endPts[c-1]+1 ... endPts[c]).
    // SAFETY: `elt.pointee.{sp,ep}` are buffers of length `contourCapacity`, and
    // `g.numContours <= glyph.contourCapacity` was asserted above, so `c` is in bounds.
    var prev: Int = -1
    for c in 0..<g.numContours {
      let last = Int(g.endPts[c])
      unsafe elt.pointee.sp[c] = UInt16(prev + 1)
      unsafe elt.pointee.ep[c] = UInt16(last)
      prev = last
    }

    // SAFETY: `elt` is `glyph.element`, valid for `self`'s lifetime. The two writes
    // are scalar field stores into the same allocation we just populated.
    unsafe elt.pointee.pointCount = Int32(n)
    unsafe elt.pointee.contourCount = Int32(g.numContours)

    // Run the glyph bytecode. fpgm/prep buffers are passed too so CALL/LOOPCALL
    // to functions defined in those programs can dereference their bytecode.
    // SAFETY: `fpgmBuf`/`prepBuf`/`glyfBuf` are valid only within their respective
    // `withUnsafeBufferPointer` closures, all of which enclose the `runProgram` call;
    // `runProgram` consumes the pointers synchronously. `twilight.element` and
    // `glyph.element` are owned by `self` for the call duration.
    try unsafe fpgmBytes.withUnsafeBufferPointer { fpgmBuf in
      try unsafe prepBytes.withUnsafeBufferPointer { prepBuf in
        try unsafe g.instructions.withUnsafeBufferPointer { glyfBuf in
          try unsafe interpreter.runProgram(
            fpgm: fpgmBuf.baseAddress, fpgmCount: Int32(fpgmBuf.count),
            prep: prepBuf.isEmpty ? nil : prepBuf.baseAddress,
            prepCount: Int32(prepBuf.count),
            glyf: glyfBuf.isEmpty ? nil : glyfBuf.baseAddress,
            glyfCount: Int32(glyfBuf.count),
            twilightZone: unsafe twilight.element,
            glyphZone: unsafe glyph.element,
            unscaledOutlineIsWrong: false,
            parBlock: &parBlock
          )
        }
      }
    }
  }
}
