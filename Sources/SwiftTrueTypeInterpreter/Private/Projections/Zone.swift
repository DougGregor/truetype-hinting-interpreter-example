internal import ContainersPreview

extension SwiftTrueTypeInterpreter {
  /// A zone's outline data, as spans over the arrays of a caller-owned `fnt_ElementType`.
  ///
  /// The zone exclusively borrows the element for its lifetime, and every access is
  /// bounds-checked by the spans. The constructors check that the element's arrays are as long
  /// as its counts claim, so callers can rely on `maxPointCount` and `maxContourCount`.
  public struct Zone: ~Copyable, ~Escapable {
    public enum ZoneType: Int32, Equatable, RawRepresentable {
      case twilight = 0
      case glyph = 1

      public init?(rawValue: Int32, maxElements: UInt16) {
        guard 0..<Int32(maxElements) ~= rawValue else { return nil }
        self = (rawValue == 0) ? .twilight : .glyph
      }
    }

    @_lifetime(&element)
    static func glyphZone(wrapping element: inout fnt_ElementType) -> Self {
      Self(.glyph, wrapping: &element)
    }

    @_lifetime(&element)
    static func twilightZone(wrapping element: inout fnt_ElementType) -> Self {
      Self(.twilight, wrapping: &element)
    }

    /// Constructs an empty Zone. `isPresent` returns false, and the bounds-checked entry
    /// points (`point(at:)`, `readContour`) refuse to proceed because their bounds are zero.
    @_lifetime(immortal)
    static func empty(_ zoneType: ZoneType) -> Self {
      Self(emptyOf: zoneType)
    }

    let zoneType: ZoneType

    let isPresent: Bool

    // Hinted coordinates, scaled unhinted coordinates, and unscaled unhinted coordinates.
    var x: MutableSpan<Int32>
    var y: MutableSpan<Int32>
    var ox: MutableSpan<Int32>
    var oy: MutableSpan<Int32>
    var oox: MutableSpan<Int16>
    var ooy: MutableSpan<Int16>
    var onCurve: MutableSpan<UInt8>
    var f: MutableSpan<UInt8>

    // Contour start and end points.
    let sp: Span<UInt16>
    let ep: Span<UInt16>

    @_lifetime(&element)
    init(_ zoneType: ZoneType, wrapping element: inout fnt_ElementType) {
      let eltPointCount = Int(element.pointCount)
      let eltMaxPointCount = Int(element.maxPointCount)
      let eltMaxContourCount = Int(element.maxContourCount)
      let eltContourCount = Int(element.contourCount)
      let phantomCount = (zoneType == .twilight) ? 0 : Int(kPrivatePhantomCount.rawValue)

      // The element must be accurate about its own sizes.
      precondition(
        0 <= eltPointCount && eltPointCount + phantomCount <= eltMaxPointCount
          && 0 <= eltContourCount && eltContourCount <= eltMaxContourCount,
        "inconsistent fnt_ElementType counts")
      precondition(
        element.x.count >= eltMaxPointCount && element.y.count >= eltMaxPointCount
          && element.ox.count >= eltMaxPointCount && element.oy.count >= eltMaxPointCount
          && element.oox.count >= eltMaxPointCount && element.ooy.count >= eltMaxPointCount
          && element.onCurve.count >= eltMaxPointCount && element.f.count >= eltMaxPointCount
          && element.sp.count >= eltMaxContourCount && element.ep.count >= eltMaxContourCount,
        "fnt_ElementType arrays are shorter than its maximum counts")

      self.zoneType = zoneType
      isPresent = true
      x = element.x.mutableSpan
      y = element.y.mutableSpan
      ox = element.ox.mutableSpan
      oy = element.oy.mutableSpan
      oox = element.oox.mutableSpan
      ooy = element.ooy.mutableSpan
      onCurve = element.onCurve.mutableSpan
      f = element.f.mutableSpan
      sp = element.sp.span
      ep = element.ep.span

      maxPointCount = eltMaxPointCount
      pointCount = eltPointCount + phantomCount
      phantomStartIndex = eltPointCount
      maxContourCount = eltMaxContourCount
      contourCount = eltContourCount
      contourIndices = 0..<contourCount
    }

    @_lifetime(immortal)
    private init(emptyOf zoneType: ZoneType) {
      self.zoneType = zoneType
      isPresent = false
      x = MutableSpan()
      y = MutableSpan()
      ox = MutableSpan()
      oy = MutableSpan()
      oox = MutableSpan()
      ooy = MutableSpan()
      onCurve = MutableSpan()
      f = MutableSpan()
      sp = Span()
      ep = Span()
      maxPointCount = 0
      pointCount = 0
      phantomStartIndex = 0
      maxContourCount = 0
      contourCount = 0
      contourIndices = 0..<0
    }

    /// Corresponds to the allocation size of the element.
    ///
    /// The maximum number of points may exceed the number of points in the glyph outline,
    /// and opcodes may access any of those points.
    let maxPointCount: Int

    /// The number of points in the glyph outline or twilight zone, including phantoms (if applicable).
    let pointCount: Int

    let phantomStartIndex: Int

    let maxContourCount: Int

    let contourCount: Int

    let contourIndices: Range<Int>

    mutating func rollback() {
      for i in 0..<(phantomStartIndex + Int(kPublicPhantomCount.rawValue)) {
        let p = try! point(at: i)
        setHinted(p, scaled(p))
      }
    }

    // MARK: Validation

    // This function replicates checks that are narrower than Zone's normal operating parameters.
    // It exists for binary compatibility: only some opcodes perform this check.
    @inline(always) @_transparent
    func check(against maxp: sfntMaxProfileTable) throws(InterpreterError) {
      guard zoneType == .glyph else { return }
      let phantomCount = Int(kPrivatePhantomCount.rawValue)
      let maxpContours = Int(max(maxp.maxContours, maxp.maxCompositeContours))
      let maxpPoints = Int(max(maxp.maxPoints, maxp.maxCompositePoints))
      if pointCount > maxpPoints + phantomCount || contourCount > maxpContours {
        throw .maxpLimitExceeded
      }
    }

    // MARK: Contour access

    @inline(always) @_transparent
    func readContour(index: Int) throws(SwiftTrueTypeInterpreter.InterpreterError) -> ClosedRange<Int> {
      guard index >= 0, index < contourCount else {
        throw .noSuchContour
      }
      let start = Int(sp[index])
      let end = Int(ep[index])
      guard start <= end else { throw .invalidOperand }
      return start...end
    }

    // MARK: Point access

    @inline(always) @_transparent
    private func validated(_ index: Int) throws(InterpreterError) -> Int {
      guard index >= 0, index < maxPointCount else {
        throw .noSuchPoint
      }
      return index
    }

    /// The hinted coordinates of the point at `index`.
    @inline(always) @_transparent
    func hinted(at index: Int) throws(InterpreterError) -> OutlineCoord {
      let i = try validated(index)
      return OutlineCoord(x: F26Dot6(bitPattern: x[i]), y: F26Dot6(bitPattern: y[i]))
    }

    /// The scaled, unhinted coordinates of the point at `index`.
    @inline(always) @_transparent
    func scaled(at index: Int) throws(InterpreterError) -> OutlineCoord {
      let i = try validated(index)
      return OutlineCoord(x: F26Dot6(bitPattern: ox[i]), y: F26Dot6(bitPattern: oy[i]))
    }

    /// The unscaled, unhinted coordinates of the point at `index`.
    @inline(always) @_transparent
    func original(at index: Int) throws(InterpreterError) -> UnscaledCoord {
      let i = try validated(index)
      return UnscaledCoord(x: oox[i], y: ooy[i])
    }

    /// A validated index of a point in a `Zone`. Making one (via ``Zone/point(at:)``) checks
    /// the index against `maxPointCount`. It is only an index: the zone's spans still check
    /// every access, so using it with a different zone is a logic error but not a memory-safety
    /// one.
    struct Point: BitwiseCopyable {
      fileprivate let index: Int

      static let ONCURVE: UInt8 = 0x01
      fileprivate static let XMOVED: UInt8 = 0x01
      fileprivate static let YMOVED: UInt8 = 0x02
    }

    /// Validates `index` and returns a `Point` for use with this zone's accessors.
    @inline(always) @_transparent
    func point(at index: Int) throws(InterpreterError) -> Point {
      Point(index: try validated(index))
    }

    @inline(always) @_transparent
    func hinted(_ p: Point) -> OutlineCoord {
      OutlineCoord(x: F26Dot6(bitPattern: x[p.index]), y: F26Dot6(bitPattern: y[p.index]))
    }

    @inline(always) @_transparent
    func scaled(_ p: Point) -> OutlineCoord {
      OutlineCoord(x: F26Dot6(bitPattern: ox[p.index]), y: F26Dot6(bitPattern: oy[p.index]))
    }

    @inline(always) @_transparent
    func original(_ p: Point) -> UnscaledCoord {
      UnscaledCoord(x: oox[p.index], y: ooy[p.index])
    }

    @inline(always) @_transparent
    mutating func setHinted(_ p: Point, _ value: OutlineCoord) {
      x[p.index] = value.x.bitPattern
      y[p.index] = value.y.bitPattern
    }

    @inline(always) @_transparent
    mutating func setScaled(_ p: Point, _ value: OutlineCoord) {
      ox[p.index] = value.x.bitPattern
      oy[p.index] = value.y.bitPattern
    }

    @inline(always) @_transparent
    mutating func setOriginal(_ p: Point, _ value: UnscaledCoord) {
      oox[p.index] = value.x
      ooy[p.index] = value.y
    }

    @inline(always) @_transparent
    mutating func toggleOnCurve(_ p: Point) {
      onCurve[p.index] ^= Point.ONCURVE
    }

    /// OR-merges the given `xMoved`/`yMoved` flags into the point's `f` byte.
    @inline(always) @_transparent
    mutating func markMoved(_ p: Point, x xMoved: Bool, y yMoved: Bool) {
      let bits: UInt8 = (xMoved ? Point.XMOVED : 0) | (yMoved ? Point.YMOVED : 0)
      if bits != 0 {
        f[p.index] |= bits
      }
    }

    /// Clears the given `xMoved`/`yMoved` flag bits from the point's `f` byte.
    @inline(always) @_transparent
    mutating func clearMoved(_ p: Point, x xMoved: Bool, y yMoved: Bool) {
      let bits: UInt8 = (xMoved ? Point.XMOVED : 0) | (yMoved ? Point.YMOVED : 0)
      if bits != 0 {
        f[p.index] &= ~bits
      }
    }
  }
}
