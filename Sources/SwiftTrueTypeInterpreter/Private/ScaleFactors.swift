extension SwiftTrueTypeInterpreter {
  /// Scaling factors and transformation parameters for TrueType hinting.
  ///
  /// Contains scaling, rotation, and stretching information used during
  /// glyph outline processing and control value table operations.
  public struct ScaleFactors {
    /// Glyph coordinate scaling vector.
    public let stretch: FixedVector<F16Dot16>

    /// Font units per em.
    public let unitsPerEm: Int16

    /// Target point size for rendering.
    public let pointSize: Int32

    /// Scaling factor for control value table entries.
    public let cvtScale: F16Dot16

    /// Whether the glyph is rotated.
    public let isRotated: Bool

    /// Whether the glyph is stretched (non-uniform scaling).
    public let isStretched: Bool

    /// Stretch vector adjusted for control value table scaling.
    public let cvtStretch: FixedVector<F16Dot16>

    /// Integer points per em for each axis.
    public let integerPointsPerEm: UnscaledCoord

    /// Scaling factor from font units to 26.6 fixed point.
    public let unitsPerEmScale: FixedVector<F16Dot16>

    /// Creates new scaling factors with default parameters.
    public init() {
      stretch = .identity
      unitsPerEm = 0
      pointSize = 0
      cvtScale = .zero
      isRotated = false
      isStretched = false
      cvtStretch = .identity
      integerPointsPerEm = .zero
      unitsPerEmScale = .zero
    }

    /// Creates new scaling factors with specified parameters.
    ///
    /// - Parameters:
    ///   - stretch: Scaling vector (defaults to identity)
    ///   - unitsPerEm: Font units per em (defaults to 0)
    ///   - pointSize: Target point size (defaults to 0)
    ///   - cvtScale: Control value table scaling factor (defaults to 0)
    ///   - rotated: Whether glyph is rotated (defaults to false)
    ///   - stretched: Whether glyph is stretched (defaults to false)
    public init(
      stretch: FixedVector<F16Dot16>,
      unitsPerEm: Int16,
      pointSize: Int32,
      cvtScale: F16Dot16,
      isRotated rotated: Bool,
      isStretched stretched: Bool
    ) {
      self.stretch = stretch
      self.unitsPerEm = unitsPerEm
      self.pointSize = pointSize
      self.cvtScale = cvtScale
      self.isRotated = rotated
      self.isStretched = stretched

      cvtStretch = stretch.dividedWithSaturation(by: cvtScale, rounding: .towardZero)
      integerPointsPerEm = .init(x: fixedRound(stretch.x), y: fixedRound(stretch.y))
      // unitsPerEmScale converts from font units to 26.6 fixed point - hence the F26Dot6.fractionBits
      unitsPerEmScale = stretch.mulDiv(
        F16Dot16(1 << F26Dot6.fractionBits),
        F16Dot16(unitsPerEm),
        rounding: .towardZero
      )
    }
  }
}

@inline(always) @_transparent
private func fixedRound(_ value: SwiftTrueTypeInterpreter.F16Dot16) -> Int16 {
  let rounded = value.roundingWithSaturation()
  return .init(rounded.bitPattern >> 16)
}
