import SwiftTrueTypeInterpreter

// SAFETY: All unsafe pointer storage (element) is allocated in init, deallocated in deinit,
// and never escapes the class. The class owns its allocation for its entire lifetime.
/// Creates and manages an `fnt_ElementType` allocation, to be passed to the TrueType interpreter by its unit tests
@safe class TestZone {
  private var _maxp: sfntMaxProfileTable
  private var _type: ZoneType
  private(set) var element: UnsafeMutablePointer<fnt_ElementType>

  init(
    type: ZoneType,
    maxp: sfntMaxProfileTable
  ) {
    _type = type
    _maxp = maxp
    let basePointCount: Int
    let allocSize: Int
    switch type {
    case .glyph:
      basePointCount = Int(max(maxp.maxPoints, maxp.maxCompositePoints))
      allocSize = basePointCount + 8  // phantoms
    case .twilight:
      basePointCount = Int(maxp.maxTwilightPoints)
      allocSize = basePointCount
    }

    let contourCount: Int
    switch type {
    case .glyph:
      contourCount = Int(max(maxp.maxContours, maxp.maxCompositeContours))
    case .twilight:
      contourCount = Int(maxp.maxTwilightPoints)
    }

    // SAFETY: All pointer operations below use freshly-allocated memory sized by the
    // computed counts above. Each allocation is owned by element.pointee and will be
    // deallocated in deinit.
    unsafe (element = UnsafeMutablePointer<fnt_ElementType>.allocate(capacity: 1))
    unsafe element.initialize(to: fnt_ElementType())

    unsafe (element.pointee.pointCount = Int32(basePointCount))
    let maxPointCount: Int32 =
    switch type {
    case .glyph: Int32(basePointCount + 8)
    case .twilight: Int32(basePointCount)
    }
    unsafe (element.pointee.maxPointCount = maxPointCount)
    unsafe (element.pointee.maxContourCount = Int32(contourCount))
    unsafe (element.pointee.contourCount = 0)

    // Allocate backing arrays
    if allocSize > 0 {
      // SAFETY: Each pointer is allocated with allocSize capacity and immediately
      // initialized. They are stored in element.pointee and deallocated in deinit.
      unsafe (element.pointee.x = .allocate(capacity: allocSize))
      unsafe (element.pointee.y = .allocate(capacity: allocSize))
      unsafe (element.pointee.ox = .allocate(capacity: allocSize))
      unsafe (element.pointee.oy = .allocate(capacity: allocSize))
      unsafe (element.pointee.oox = .allocate(capacity: allocSize))
      unsafe (element.pointee.ooy = .allocate(capacity: allocSize))
      unsafe (element.pointee.onCurve = .allocate(capacity: allocSize))
      unsafe (element.pointee.f = .allocate(capacity: allocSize))

      // Zero-init
      unsafe element.pointee.x.initialize(repeating: 0, count: allocSize)
      unsafe element.pointee.y.initialize(repeating: 0, count: allocSize)
      unsafe element.pointee.ox.initialize(repeating: 0, count: allocSize)
      unsafe element.pointee.oy.initialize(repeating: 0, count: allocSize)
      unsafe element.pointee.oox.initialize(repeating: 0, count: allocSize)
      unsafe element.pointee.ooy.initialize(repeating: 0, count: allocSize)
      unsafe element.pointee.onCurve.initialize(repeating: 0, count: allocSize)
      unsafe element.pointee.f.initialize(repeating: 0, count: allocSize)
    }

    if contourCount > 0 {
      // SAFETY: sp/ep are allocated with contourCount capacity and immediately
      // initialized. Subscript at [0] is valid when basePointCount > 0
      // because contourCount > 0 implies at least one contour slot.
      unsafe (element.pointee.sp = .allocate(capacity: contourCount))
      unsafe (element.pointee.ep = .allocate(capacity: contourCount))
      unsafe element.pointee.sp.initialize(repeating: 0, count: contourCount)
      unsafe element.pointee.ep.initialize(repeating: 0, count: contourCount)

      // Default contour covering all outline points (not phantoms)
      if basePointCount > 0 {
        unsafe (element.pointee.ep[0] = UInt16(basePointCount - 1))
        unsafe (element.pointee.contourCount = 1)
      }
    }
  }

  deinit {
    // SAFETY: element was allocated in init and is valid for the class lifetime.
    // All sub-allocations are deallocated before element itself.
    let pointSize = Int(unsafe element.pointee.maxPointCount)
    let contourCount = Int(unsafe element.pointee.maxContourCount)

    if pointSize > 0 {
      // SAFETY: These pointers were allocated in init (or growZone) with
      // maxPointCount capacity and are being deallocated exactly once.
      unsafe element.pointee.x.deallocate()
      unsafe element.pointee.y.deallocate()
      unsafe element.pointee.ox.deallocate()
      unsafe element.pointee.oy.deallocate()
      unsafe element.pointee.oox.deallocate()
      unsafe element.pointee.ooy.deallocate()
      unsafe element.pointee.onCurve.deallocate()
      unsafe element.pointee.f.deallocate()
    }

    if contourCount > 0 {
      // SAFETY: sp/ep were allocated in init with contourCount capacity.
      unsafe element.pointee.sp.deallocate()
      unsafe element.pointee.ep.deallocate()
    }

    unsafe element.deallocate()
  }

  private func growZone(to newCapacity: Int32) {
    // SAFETY: element.pointee is valid for the class lifetime; all pointer
    // arithmetic uses computed sizes that match actual allocation capacities.
    let oldCapacity = unsafe element.pointee.maxPointCount
    guard newCapacity > oldCapacity else { return }

    let newSize = Int(newCapacity)
    let oldSize = Int(oldCapacity)

    // Allocate new arrays
    let newX = UnsafeMutablePointer<Int32>.allocate(capacity: newSize)
    let newY = UnsafeMutablePointer<Int32>.allocate(capacity: newSize)
    let newOX = UnsafeMutablePointer<Int32>.allocate(capacity: newSize)
    let newOY = UnsafeMutablePointer<Int32>.allocate(capacity: newSize)
    let newOOX = UnsafeMutablePointer<Int16>.allocate(capacity: newSize)
    let newOOY = UnsafeMutablePointer<Int16>.allocate(capacity: newSize)
    let newOnCurve = UnsafeMutablePointer<UInt8>.allocate(capacity: newSize)
    let newF = UnsafeMutablePointer<UInt8>.allocate(capacity: newSize)

    // Copy existing data
    if oldSize > 0 {
      // SAFETY: Source pointers are valid with oldSize capacity (from init or
      // prior growZone). Destination pointers were just allocated with newSize
      // >= oldSize. No overlap since these are separate allocations.
      unsafe newX.initialize(from: element.pointee.x, count: oldSize)
      unsafe newY.initialize(from: element.pointee.y, count: oldSize)
      unsafe newOX.initialize(from: element.pointee.ox, count: oldSize)
      unsafe newOY.initialize(from: element.pointee.oy, count: oldSize)
      unsafe newOOX.initialize(from: element.pointee.oox, count: oldSize)
      unsafe newOOY.initialize(from: element.pointee.ooy, count: oldSize)
      unsafe newOnCurve.initialize(from: element.pointee.onCurve, count: oldSize)
      unsafe newF.initialize(from: element.pointee.f, count: oldSize)
    }

    // Zero-init new portion
    let remaining = newSize - oldSize
    if remaining > 0 {
      // SAFETY: advanced(by: oldSize) is within bounds because newSize > oldSize
      // and each pointer was allocated with newSize capacity.
      unsafe newX.advanced(by: oldSize).initialize(repeating: 0, count: remaining)
      unsafe newY.advanced(by: oldSize).initialize(repeating: 0, count: remaining)
      unsafe newOX.advanced(by: oldSize).initialize(repeating: 0, count: remaining)
      unsafe newOY.advanced(by: oldSize).initialize(repeating: 0, count: remaining)
      unsafe newOOX.advanced(by: oldSize).initialize(repeating: 0, count: remaining)
      unsafe newOOY.advanced(by: oldSize).initialize(repeating: 0, count: remaining)
      unsafe newOnCurve.advanced(by: oldSize).initialize(repeating: 0, count: remaining)
      unsafe newF.advanced(by: oldSize).initialize(repeating: 0, count: remaining)
    }

    // Free old arrays
    if oldSize > 0 {
      // SAFETY: These are the old allocations being replaced; each is
      // deallocated exactly once before reassignment below.
      unsafe element.pointee.x.deallocate()
      unsafe element.pointee.y.deallocate()
      unsafe element.pointee.ox.deallocate()
      unsafe element.pointee.oy.deallocate()
      unsafe element.pointee.oox.deallocate()
      unsafe element.pointee.ooy.deallocate()
      unsafe element.pointee.onCurve.deallocate()
      unsafe element.pointee.f.deallocate()
    }

    // Assign new arrays
    // SAFETY: Replacing element.pointee storage with the freshly-allocated pointers.
    // Old pointers were deallocated above; new pointers are valid with newSize capacity.
    unsafe (element.pointee.x = newX)
    unsafe (element.pointee.y = newY)
    unsafe (element.pointee.ox = newOX)
    unsafe (element.pointee.oy = newOY)
    unsafe (element.pointee.oox = newOOX)
    unsafe (element.pointee.ooy = newOOY)
    unsafe (element.pointee.onCurve = newOnCurve)
    unsafe (element.pointee.f = newF)
    unsafe (element.pointee.maxPointCount = newCapacity)
  }

  private func readPoint(at index: Int) -> OutlinePoint {
    // SAFETY: Callers ensure index < maxPointCount. All pointer arrays were
    // allocated with at least maxPointCount capacity in init or growZone.
    unsafe OutlinePoint(
      original: .init(
        x: element.pointee.oox.advanced(by: index).pointee,
        y: element.pointee.ooy.advanced(by: index).pointee
      ),
      scaled: .init(
        x: .init(bitPattern: element.pointee.ox.advanced(by: index).pointee),
        y: .init(bitPattern: element.pointee.oy.advanced(by: index).pointee)
      ),
      hinted: .init(
        x: .init(bitPattern: element.pointee.x.advanced(by: index).pointee),
        y: .init(bitPattern: element.pointee.y.advanced(by: index).pointee)
      ),
      onCurve: element.pointee.onCurve.advanced(by: index).pointee & 0x01 != 0,
      xMoved: element.pointee.f.advanced(by: index).pointee & 0x01 != 0,
      yMoved: element.pointee.f.advanced(by: index).pointee & 0x02 != 0
    )
  }

  private func writePoint(_ value: OutlinePoint, at index: Int) {
    // SAFETY: Callers ensure index < maxPointCount. All pointer arrays were
    // allocated with at least maxPointCount capacity in init or growZone.
    unsafe element.pointee.x.advanced(by: index).pointee = value.hinted.x.bitPattern
    unsafe element.pointee.y.advanced(by: index).pointee = value.hinted.y.bitPattern
    unsafe element.pointee.ox.advanced(by: index).pointee = value.scaled.x.bitPattern
    unsafe element.pointee.oy.advanced(by: index).pointee = value.scaled.y.bitPattern
    unsafe element.pointee.oox.advanced(by: index).pointee = value.original.x
    unsafe element.pointee.ooy.advanced(by: index).pointee = value.original.y

    var onCurve: UInt8 = unsafe element.pointee.onCurve.advanced(by: index).pointee & ~0x01
    if value.onCurve { onCurve |= 0x01 }
    unsafe (element.pointee.onCurve.advanced(by: index).pointee = onCurve)

    var flags: UInt8 = 0
    if value.xMoved { flags |= 0x01 }
    if value.yMoved { flags |= 0x02 }
    unsafe (element.pointee.f.advanced(by: index).pointee = flags)
  }

  var points: [OutlinePoint] {
    get {
      // SAFETY: element.pointee.maxPointCount reflects actual allocation capacity.
      (0..<Int(unsafe element.pointee.maxPointCount)).map { readPoint(at: $0) }
    }
    set {
      let newCount = Int32(newValue.count)
      growZone(to: newCount)
      // SAFETY: element.pointee.maxPointCount is valid after growZone ensures capacity.
      precondition(unsafe newCount <= element.pointee.maxPointCount)

      var index = 0
      for value in newValue {
        defer { index += 1 }
        writePoint(value, at: index)
      }

      // Zero out untouched points
      while index < Int(unsafe element.pointee.maxPointCount) {
        defer { index += 1 }
        writePoint(.zero, at: index)
      }

      // SAFETY: pointCount and contour bookkeeping access element.pointee which
      // is valid for the class lifetime. Subscript [0] is valid because
      // maxContourCount > 0 implies at least one contour slot was allocated.
      let pointCount: Int32 =
      switch _type {
      case .twilight: newCount
      case .glyph: newCount - 8  // privatePhantomCount
      }
      unsafe (element.pointee.pointCount = pointCount)

      // Set up a default contour covering all outline points
      if unsafe element.pointee.maxContourCount > 0 && element.pointee.pointCount > 0 {
        unsafe (element.pointee.sp[0] = 0)
        unsafe (element.pointee.ep[0] = UInt16(element.pointee.pointCount - 1))
        unsafe (element.pointee.contourCount = 1)
      }
    }
  }

  var contours: [ClosedRange<Int>] {
    get {
      // SAFETY: element.pointee.maxContourCount reflects actual contour allocation
      // capacity. sp/ep arrays are valid up to that count.
      (0..<Int(unsafe element.pointee.maxContourCount)).map { index in
        Int(
          unsafe element.pointee.sp.advanced(by: index).pointee
        )...Int(
          unsafe element.pointee.ep.advanced(by: index).pointee
        )
      }
    }
    set {
      // SAFETY: element.pointee.maxContourCount is valid; the precondition
      // ensures we don't write past allocated capacity.
      precondition(
        unsafe newValue.count <= element.pointee.maxContourCount,
        "contour growth not implemented, can you initialize the zone with a larger maxp.maxContours?"
      )

      // Index shenanigans in case `newValue.startIndex != 0`
      var index = 0
      for value in newValue {
        defer { index += 1 }
        unsafe element.pointee.sp.advanced(by: index).pointee = UInt16(value.lowerBound)
        unsafe element.pointee.ep.advanced(by: index).pointee = UInt16(value.upperBound)
      }

      // Zero out untouched points
      while index < Int(unsafe element.pointee.maxContourCount) {
        defer { index += 1 }
        unsafe element.pointee.sp.advanced(by: index).pointee = 0
        unsafe element.pointee.ep.advanced(by: index).pointee = 0
      }

      unsafe (element.pointee.contourCount = Int32(newValue.endIndex))
    }
  }

  var outlinePoints: [OutlinePoint] {
    // SAFETY: element.pointee.pointCount is maintained consistently by points setter.
    get { Array(points[0..<Int(unsafe element.pointee.pointCount)]) }
    set { points = _type == .twilight ? newValue : newValue + phantomPoints(forOutlinePoints: newValue) }
  }
}
