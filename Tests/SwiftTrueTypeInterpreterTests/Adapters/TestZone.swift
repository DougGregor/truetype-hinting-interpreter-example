import SwiftTrueTypeInterpreter

/// Creates and manages an `fnt_ElementType`, to be passed to the TrueType interpreter by its unit tests
final class TestZone {
  private var _maxp: sfntMaxProfileTable
  private var _type: ZoneType
  var element: fnt_ElementType

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

    element = fnt_ElementType()
    element.pointCount = Int32(basePointCount)
    element.maxPointCount = Int32(allocSize)
    element.maxContourCount = Int32(contourCount)
    element.contourCount = 0

    element.x = .init(repeating: 0, count: allocSize)
    element.y = .init(repeating: 0, count: allocSize)
    element.ox = .init(repeating: 0, count: allocSize)
    element.oy = .init(repeating: 0, count: allocSize)
    element.oox = .init(repeating: 0, count: allocSize)
    element.ooy = .init(repeating: 0, count: allocSize)
    element.onCurve = .init(repeating: 0, count: allocSize)
    element.f = .init(repeating: 0, count: allocSize)
    element.sp = .init(repeating: 0, count: contourCount)
    element.ep = .init(repeating: 0, count: contourCount)

    // Default contour covering all outline points (not phantoms)
    if contourCount > 0 && basePointCount > 0 {
      element.ep[0] = UInt16(basePointCount - 1)
      element.contourCount = 1
    }
  }

  private func growZone(to newCapacity: Int32) {
    let newSize = Int(newCapacity)
    guard newSize > Int(element.maxPointCount) else { return }

    // New points are zero-initialized.
    func grow<T: FixedWidthInteger>(_ array: inout UniqueArray<T>) {
      array.reserveCapacity(newSize)
      while array.count < newSize {
        array.append(0)
      }
    }
    grow(&element.x)
    grow(&element.y)
    grow(&element.ox)
    grow(&element.oy)
    grow(&element.oox)
    grow(&element.ooy)
    grow(&element.onCurve)
    grow(&element.f)
    element.maxPointCount = newCapacity
  }

  private func readPoint(at index: Int) -> OutlinePoint {
    OutlinePoint(
      original: .init(x: element.oox[index], y: element.ooy[index]),
      scaled: .init(x: .init(bitPattern: element.ox[index]), y: .init(bitPattern: element.oy[index])),
      hinted: .init(x: .init(bitPattern: element.x[index]), y: .init(bitPattern: element.y[index])),
      onCurve: element.onCurve[index] & 0x01 != 0,
      xMoved: element.f[index] & 0x01 != 0,
      yMoved: element.f[index] & 0x02 != 0
    )
  }

  private func writePoint(_ value: OutlinePoint, at index: Int) {
    element.x[index] = value.hinted.x.bitPattern
    element.y[index] = value.hinted.y.bitPattern
    element.ox[index] = value.scaled.x.bitPattern
    element.oy[index] = value.scaled.y.bitPattern
    element.oox[index] = value.original.x
    element.ooy[index] = value.original.y

    var onCurve: UInt8 = element.onCurve[index] & ~0x01
    if value.onCurve { onCurve |= 0x01 }
    element.onCurve[index] = onCurve

    var flags: UInt8 = 0
    if value.xMoved { flags |= 0x01 }
    if value.yMoved { flags |= 0x02 }
    element.f[index] = flags
  }

  var points: [OutlinePoint] {
    get {
      (0..<Int(element.maxPointCount)).map { readPoint(at: $0) }
    }
    set {
      let newCount = Int32(newValue.count)
      growZone(to: newCount)
      precondition(newCount <= element.maxPointCount)

      var index = 0
      for value in newValue {
        defer { index += 1 }
        writePoint(value, at: index)
      }

      // Zero out untouched points
      while index < Int(element.maxPointCount) {
        defer { index += 1 }
        writePoint(.zero, at: index)
      }

      let pointCount: Int32 =
      switch _type {
      case .twilight: newCount
      case .glyph: newCount - 8  // privatePhantomCount
      }
      element.pointCount = pointCount

      // Set up a default contour covering all outline points
      if element.maxContourCount > 0 && element.pointCount > 0 {
        element.sp[0] = 0
        element.ep[0] = UInt16(element.pointCount - 1)
        element.contourCount = 1
      }
    }
  }

  var contours: [ClosedRange<Int>] {
    get {
      (0..<Int(element.maxContourCount)).map { index in
        Int(element.sp[index])...Int(element.ep[index])
      }
    }
    set {
      precondition(
        newValue.count <= element.maxContourCount,
        "contour growth not implemented, can you initialize the zone with a larger maxp.maxContours?"
      )

      // Index shenanigans in case `newValue.startIndex != 0`
      var index = 0
      for value in newValue {
        defer { index += 1 }
        element.sp[index] = UInt16(value.lowerBound)
        element.ep[index] = UInt16(value.upperBound)
      }

      // Zero out untouched points
      while index < Int(element.maxContourCount) {
        defer { index += 1 }
        element.sp[index] = 0
        element.ep[index] = 0
      }

      element.contourCount = Int32(newValue.endIndex)
    }
  }

  var outlinePoints: [OutlinePoint] {
    get { Array(points[0..<Int(element.pointCount)]) }
    set { points = _type == .twilight ? newValue : newValue + phantomPoints(forOutlinePoints: newValue) }
  }
}
