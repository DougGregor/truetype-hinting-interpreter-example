internal import ContainersPreview

// Sentinel `fnt_ElementType` instance (zero-initialized) used as the borrow source for empty
// `Zone`s. All counts on an empty Zone are zero so its accessors short-circuit before they
// could read through `_element.value`; the sentinel only needs a stable address so that the
// `Ref` it backs has somewhere to point.
private nonisolated(unsafe) let _emptyZoneSentinelElement = unsafe fnt_ElementType()

extension SwiftTrueTypeInterpreter {
  // Zone provides bounds and lifetime safety to callers based on the premises described in `init(_:wrapping:)`.
  @safe public struct Zone: ~Copyable, ~Escapable {
    public enum ZoneType: Int32, Equatable, RawRepresentable {
      case twilight = 0
      case glyph = 1

      public init?(rawValue: Int32, maxElements: UInt16) {
        guard 0..<Int32(maxElements) ~= rawValue else { return nil }
        self = (rawValue == 0) ? .twilight : .glyph
      }
    }

    @_lifetime(copy element)
    static func glyphZone(wrapping element: Ref<fnt_ElementType>) -> Self {
      // SAFETY: `element` is passed unchanged to `init(_:wrapping:)`,
      // which carries the wrapping-Zone contract.
      unsafe Self(.glyph, wrapping: element)
    }

    @_lifetime(copy element)
    static func twilightZone(wrapping element: Ref<fnt_ElementType>) -> Self {
      // SAFETY: `element` is passed unchanged to `init(_:wrapping:)`,
      // which carries the wrapping-Zone contract.
      unsafe Self(.twilight, wrapping: element)
    }

    // Constructs an empty Zone. `isPresent` returns false, and the bounds-checked entry
    // points (`point(at:)`, `readContour`) refuse to proceed because their bounds are zero.
    // Keeps an `anchoredBy:` parameter only because `Ref` (which `_element` stores) has no
    // immortal initializer; the resulting Zone is anchored to that scope but never reads
    // through `_element.value`.
    @_lifetime(copy anchor)
    static func empty<Anchor: ~Copyable & ~Escapable>(
      _ zoneType: ZoneType,
      anchoredBy anchor: borrowing Anchor
    ) -> Self {
      Self(emptyOf: zoneType, anchoredBy: anchor)
    }

    let zoneType: ZoneType

    // For non-empty Zones: a `Ref` to a valid initialized `fnt_ElementType` per the wrapping
    // init's premise. For empty Zones: a `Ref` to `_emptyZoneSentinelElement`, never read
    // through (all counts are zero so every access method short-circuits).
    let _element: Ref<fnt_ElementType>

    let isPresent: Bool

    @_lifetime(copy element)
    init(_ zoneType: ZoneType, wrapping element: Ref<fnt_ElementType>) {
      self.zoneType = zoneType
      // SAFETY: the `fnt_ElementType` passed by the caller must satisfy:
      // - `maxPointCount`/`pointCount`, `maxContourCount`/`contourCount` are accurate
      //   and `pointCount ≤ maxPointCount`, `contourCount ≤ maxContourCount`.
      // - `x`, `y`, `ox`, `oy`, `oox`, `ooy`, `onCurve`, and `f` point at parallel
      //   arrays of length ≥ `maxPointCount`.
      // - `sp`, `ep` point at arrays of length ≥ `maxContourCount`.
      unsafe _element = element
      isPresent = true
      let (eltPointCount, eltMaxPointCount, eltMaxContourCount, eltContourCount) = unsafe (
        Int(element.value.pointCount),
        Int(element.value.maxPointCount),
        Int(element.value.maxContourCount),
        Int(element.value.contourCount)
      )
      let phantomCount = (zoneType == .twilight) ? 0 : Int(kPrivatePhantomCount.rawValue)

      maxPointCount = eltMaxPointCount
      pointCount = eltPointCount + phantomCount
      phantomStartIndex = eltPointCount
      assert(maxPointCount >= pointCount)
      assert(maxPointCount >= phantomStartIndex)

      maxContourCount = eltMaxContourCount
      contourCount = eltContourCount
      contourIndices = 0..<contourCount
    }

    // Empty initializer. Constructs `_element` as a `Ref` borrowing
    // `_emptyZoneSentinelElement` (a process-lifetime `let`) and rebinds its lifetime to
    // `anchor`'s — this is sound because the sentinel outlives any caller-provided anchor.
    // All counts are zero so every access method short-circuits before it could read
    // through `_element.value`.
    @_lifetime(copy anchor)
    private init<Anchor: ~Copyable & ~Escapable>(
      emptyOf zoneType: ZoneType,
      anchoredBy anchor: borrowing Anchor
    ) {
      self.zoneType = zoneType
      // SAFETY: `_emptyZoneSentinelElement` is a process-lifetime `let`; the `Ref`
      // borrowing it is sound to keep alive arbitrarily long. `_overrideLifetime`
      // narrows that lifetime to `copy anchor`, matching this init's annotation.
      // `_element.value` is never read — every access method's precondition fails
      // first because the counts below are all zero.
      let sentinelRef = unsafe Ref(_emptyZoneSentinelElement)
      unsafe _element = _overrideLifetime(sentinelRef, copying: anchor)
      isPresent = false
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

    // MARK: - Typed `Span` accessors for contour endpoints
    //
    // Each accessor returns a fresh `Span` whose lifetime is bounded by `borrow self`.
    // The span lives only for the expression that holds it; subsequent calls on `self`
    // are free to take a new span.

    @_lifetime(borrow self)
    @inline(always) @_transparent
    func sp() -> Span<UInt16> {
      precondition(maxContourCount > 0)
      // SAFETY: `_element.value.sp` is a valid array of length `maxContourCount` per
      // `init(_:wrapping:)` premises. The returned `Span`'s lifetime is bounded by
      // `borrow self`, so the underlying allocation is valid while the span is live.
      return unsafe Span(_unsafeStart: _element.value.sp, count: maxContourCount)
    }

    @_lifetime(borrow self)
    @inline(always) @_transparent
    func ep() -> Span<UInt16> {
      precondition(maxContourCount > 0)
      // SAFETY: `_element.value.ep` is a valid array of length `maxContourCount` per
      // `init(_:wrapping:)` premises. The returned `Span`'s lifetime is bounded by
      // `borrow self`, so the underlying allocation is valid while the span is live.
      return unsafe Span(_unsafeStart: _element.value.ep, count: maxContourCount)
    }

    // Returns a `MutableSpan` over the on-curve flag bytes. Lifetime is bound to an
    // exclusive `&self` borrow: callers store the result in a `var`, index-assign into
    // it, and the borrow releases when the local goes out of scope.
    @_lifetime(&self)
    @inline(always) @_transparent
    mutating func mutableOnCurve() -> MutableSpan<UInt8> {
      precondition(maxPointCount > 0)
      // SAFETY: `_element.value.onCurve` is a valid array of length `maxPointCount` per
      // `init(_:wrapping:)` premises. The precondition above rules out the empty `Zone`;
      // for non-empty Zones, dereferencing `_element` is safe. The returned `MutableSpan`'s
      // lifetime is bounded by `&self`, so it has exclusive access to the underlying storage
      // for its lifetime.
      return unsafe MutableSpan(_unsafeStart: _element.value.onCurve, count: maxPointCount)
    }

    func rollback() {
      for i in 0..<(phantomStartIndex + Int(kPublicPhantomCount.rawValue)) {
        var p = try! point(at: i)
        p.setHinted(p.scaled())
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
      let start = Int(sp()[index])
      let end = Int(ep()[index])
      guard start <= end else { throw .invalidOperand }
      return start...end
    }

    // MARK: Point access/in-place mutation

    /// Hands out a bounds-checked handle to a single point at `index`. The handle
    /// stores the host Zone's `_element` and the validated `index`, so subsequent
    /// reads/writes through it skip the per-call bounds check.
    @_lifetime(borrow self)
    @inline(always) @_transparent
    func point(at index: Int) throws(InterpreterError) -> Point {
      guard index >= 0, index < maxPointCount else {
        throw .noSuchPoint
      }
      // SAFETY: bounds checked above; `_element` valid per Zone construction premises.
      return Point(borrowing: self, index)
    }

    struct AxisCoords: ~Escapable, ~Copyable {
      var hinted: MutableSpan<Int32>
      let scaled: Span<Int32>
      let original: Span<Int16>
      private let f: Span<UInt8>
      let axis: Axis

      @_lifetime(&zone)
      @inline(always) @_transparent
      init(zone: inout Zone, axis: Axis) {
        self.axis = axis
        // SAFETY: each span is derived from a parallel array hanging off
        // `zone._element.value`, sized by `zone.maxPointCount` per the Zone init
        // premises. The `inout zone` parameter ensures exclusive access for the
        // lifetime of this `AxisCoords`, so the resulting `MutableSpan` cannot
        // alias another view of the same Zone.
        switch axis {
        case .x:
          unsafe hinted = MutableSpan(_unsafeStart: zone._element.value.x, count: zone.maxPointCount)
          unsafe scaled = Span(_unsafeStart: zone._element.value.ox, count: zone.maxPointCount)
          unsafe original = Span(_unsafeStart: zone._element.value.oox, count: zone.maxPointCount)
          unsafe f = Span(_unsafeStart: zone._element.value.f, count: zone.maxPointCount)
        case .y:
          unsafe hinted = MutableSpan(_unsafeStart: zone._element.value.y, count: zone.maxPointCount)
          unsafe scaled = Span(_unsafeStart: zone._element.value.oy, count: zone.maxPointCount)
          unsafe original = Span(_unsafeStart: zone._element.value.ooy, count: zone.maxPointCount)
          unsafe f = Span(_unsafeStart: zone._element.value.f, count: zone.maxPointCount)
        }
      }

      @inline(always) @_transparent
      func isMoved(at index: Int) -> Bool {
        f[index] & axis.rawValue != 0
      }
    }

    /// A bounds-checked handle to a single point in a `Zone`. Construction (via
    /// ``Zone/point(at:)``) validates the index against `maxPointCount`, and the validated
    /// index is then baked into the handle. Subsequent reads and writes through the handle
    /// trust that bound and skip the per-call check.
    @safe struct Point: ~Copyable, ~Escapable {
      // SAFETY: `_element` is a copy of the host `Zone`'s `Ref<fnt_ElementType>` (valid per
      // Zone init's premises); `_index` is bounds-checked against `maxPointCount` at
      // construction time and `Point` borrows the host Zone, so the underlying allocation
      // outlives `self`.
      fileprivate let _element: Ref<fnt_ElementType>
      fileprivate let _index: Int

      @_lifetime(borrow zone)
      @inline(always) @_transparent
      fileprivate init(borrowing zone: borrowing Zone, _ index: Int) {
        // SAFETY: `zone._element` is valid per `init(_:wrapping:)` premises. `Point` borrows
        // `zone` (`@_lifetime(borrow zone)`), and `Zone` is `~Escapable`, so the underlying
        // allocation outlives `self`. `index` is bounds-checked against `maxPointCount` by
        // the caller `Zone.point(at:)` before reaching here. The `unsafe` is propagated by
        // strict memory safety from `@unsafe fnt_ElementType`, not from any pointer
        // operation.
        unsafe _element = zone._element
        _index = index
      }

      @inline(always) @_transparent
      func hinted() -> OutlineCoord {
        // SAFETY: `_element.value` is valid per Zone init premises; `.x`/`.y` are
        // parallel arrays sized by `maxPointCount`; `_index` was bounds-checked against
        // `maxPointCount` at construction.
        unsafe OutlineCoord(
          x: F26Dot6(bitPattern: _element.value.x.advanced(by: _index).pointee),
          y: F26Dot6(bitPattern: _element.value.y.advanced(by: _index).pointee)
        )
      }

      @inline(always) @_transparent
      func scaled() -> OutlineCoord {
        // SAFETY: `_element.value` is valid per Zone init premises; `.ox`/`.oy` are
        // parallel arrays sized by `maxPointCount`; `_index` was bounds-checked against
        // `maxPointCount` at construction.
        unsafe OutlineCoord(
          x: F26Dot6(bitPattern: _element.value.ox.advanced(by: _index).pointee),
          y: F26Dot6(bitPattern: _element.value.oy.advanced(by: _index).pointee)
        )
      }

      @inline(always) @_transparent
      func original() -> UnscaledCoord {
        // SAFETY: `_element.value` is valid per Zone init premises; `.oox`/`.ooy` are
        // parallel arrays sized by `maxPointCount`; `_index` was bounds-checked against
        // `maxPointCount` at construction.
        unsafe UnscaledCoord(
          x: _element.value.oox.advanced(by: _index).pointee,
          y: _element.value.ooy.advanced(by: _index).pointee
        )
      }

      @inline(always) @_transparent
      mutating func setHinted(_ value: OutlineCoord) {
        // SAFETY: `_element.value` is valid per Zone init premises; `.x`/`.y` are
        // parallel arrays sized by `maxPointCount`; `_index` was bounds-checked against
        // `maxPointCount` at construction.
        unsafe _element.value.x.advanced(by: _index).pointee = value.x.bitPattern
        unsafe _element.value.y.advanced(by: _index).pointee = value.y.bitPattern
      }

      @inline(always) @_transparent
      mutating func setScaled(_ value: OutlineCoord) {
        // SAFETY: `_element.value` is valid per Zone init premises; `.ox`/`.oy` are
        // parallel arrays sized by `maxPointCount`; `_index` was bounds-checked against
        // `maxPointCount` at construction.
        unsafe _element.value.ox.advanced(by: _index).pointee = value.x.bitPattern
        unsafe _element.value.oy.advanced(by: _index).pointee = value.y.bitPattern
      }

      @inline(always) @_transparent
      mutating func setOriginal(_ value: UnscaledCoord) {
        // SAFETY: `_element.value` is valid per Zone init premises; `.oox`/`.ooy` are
        // parallel arrays sized by `maxPointCount`; `_index` was bounds-checked against
        // `maxPointCount` at construction.
        unsafe _element.value.oox.advanced(by: _index).pointee = value.x
        unsafe _element.value.ooy.advanced(by: _index).pointee = value.y
      }

      static let ONCURVE: UInt8 = 0x01
      mutating func toggleOnCurve() {
        // SAFETY: `_element.value` is valid per Zone init premises; `.onCurve` is an
        // array sized by `maxPointCount`; `_index` was bounds-checked against
        // `maxPointCount` at construction.
        unsafe _element.value.onCurve.advanced(by: _index).pointee ^= Self.ONCURVE
      }

      private static let XMOVED: UInt8 = 0x01
      private static let YMOVED: UInt8 = 0x02

      /// OR-merges the given `xMoved`/`yMoved` flags into the point's `f` byte.
      @inline(always) @_transparent
      mutating func markMoved(x: Bool, y: Bool) {
        let bits: UInt8 = (x ? Self.XMOVED : 0) | (y ? Self.YMOVED : 0)
        if bits != 0 {
          // SAFETY: `_element.value` is valid per Zone init premises; `.f` is an array
          // sized by `maxPointCount`; `_index` was bounds-checked against `maxPointCount`
          // at construction.
          unsafe _element.value.f.advanced(by: _index).pointee |= bits
        }
      }

      /// Clears the given `xMoved`/`yMoved` flag bits from the point's `f` byte.
      @inline(always) @_transparent
      mutating func clearMoved(x: Bool, y: Bool) {
        let bits: UInt8 = (x ? Self.XMOVED : 0) | (y ? Self.YMOVED : 0)
        if bits != 0 {
          // SAFETY: `_element.value` is valid per Zone init premises; `.f` is an array
          // sized by `maxPointCount`; `_index` was bounds-checked against `maxPointCount`
          // at construction.
          unsafe _element.value.f.advanced(by: _index).pointee &= ~bits
        }
      }
    }
  }
}
