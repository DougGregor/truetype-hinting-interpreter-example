import Darwin

extension SwiftTrueTypeInterpreter {
  /// Coordinate axes.
  public enum Axis: UInt8 {
    /// X axis (horizontal).
    case x = 0x01
    /// Y axis (vertical).
    case y = 0x02
  }

  /// Protocol for 2D Cartesian coordinates using fixed-point arithmetic.
  public protocol FixedCartesian: ~Copyable, ~Escapable {
    associatedtype Fixed: FixedPoint
    typealias Distance = FixedVector<Fixed>

    /// X coordinate component.
    var x: Fixed { get }
    /// Y coordinate component.
    var y: Fixed { get }
  }

  /// Type alias for outline coordinates (26.6 fixed-point).
  public typealias OutlineCoord = FixedCoord<F26Dot6>

  /// 2D coordinate using fixed-point arithmetic.
  public struct FixedCoord<Fixed: FixedPoint>: FixedCartesian, Hashable {
    /// X coordinate component.
    public var x: Fixed
    /// Y coordinate component.
    public var y: Fixed

    /// Creates a coordinate with the specified x and y components.
    ///
    /// - Parameters:
    ///   - x: X coordinate component
    ///   - y: Y coordinate component
    public init(x: Fixed, y: Fixed) {
      self.x = x
      self.y = y
    }
  }

  /// 2D vector using fixed-point arithmetic.
  public struct FixedVector<Fixed: FixedPoint>: FixedCartesian, Hashable {
    /// X vector component.
    public var x: Fixed
    /// Y vector component.
    public var y: Fixed

    /// Creates a vector with the specified x and y components.
    ///
    /// - Parameters:
    ///   - x: X vector component
    ///   - y: Y vector component
    public init(x: Fixed, y: Fixed) {
      self.x = x
      self.y = y
    }

    /// Creates a vector by converting from another fixed-point type.
    ///
    /// - Parameter other: Source vector to convert from
    public init<Other: FixedCartesian>(convertingIfNeeded other: Other) {
      self.init(x: Fixed(other.x), y: Fixed(other.y))
    }

    /// The identity vector.
    @inline(always) @_transparent
    public static var identity: Self { .init(x: 1, y: 1) }

    /// The zero vector.
    @inline(always) @_transparent
    public static var zero: Self { .init(x: 0, y: 0) }

    /// Unit vector along X axis.
    @inline(always) @_transparent
    public static var x_axis: Self { .init(x: 1, y: 0) }

    /// Unit vector along Y axis.
    @inline(always) @_transparent
    public static var y_axis: Self { .init(x: 0, y: 1) }

    /// Divides vector components by scalar with saturation.
    ///
    /// - Parameters:
    ///   - other: Divisor value
    ///   - rule: Rounding rule to apply
    /// - Returns: Vector with divided components
    @inline(always) @_transparent
    public func dividedWithSaturation(
      by other: Fixed,
      rounding rule: RoundingRule = Fixed.defaultRounding
    ) -> Self {
      .init(
        x: self.x.dividedWithSaturation(by: other, rounding: rule),
        y: self.y.dividedWithSaturation(by: other, rounding: rule)
      )
    }

    /// Multiplies vector by scalar and divides by another scalar.
    ///
    /// - Parameters:
    ///   - a: Multiplier value
    ///   - b: Divisor value
    ///   - rule: Rounding rule to apply
    /// - Returns: Vector with calculated components
    @inline(always) @_transparent
    public func mulDiv(_ a: Fixed, _ b: Fixed, rounding rule: RoundingRule = Fixed.defaultRounding) -> Self {
      .init(
        x: x.mulDiv(a, b, rounding: rule),
        y: y.mulDiv(a, b, rounding: rule)
      )
    }
  }

  /// 2D coordinate using 16-bit integer components for representing unscaled points.
  public struct UnscaledCoord: Hashable {
    /// Component type for coordinates.
    public typealias Component = Int16

    /// X coordinate component.
    public var x: Component
    /// Y coordinate component.
    public var y: Component

    /// The zero vector.
    @inline(always) @_transparent
    public static var zero: Self { .init(x: 0, y: 0) }

    /// Creates a coordinate with the specified x and y components.
    ///
    /// - Parameters:
    ///   - x: X coordinate component
    ///   - y: Y coordinate component
    public init(x: Component, y: Component) {
      self.x = x
      self.y = y
    }

    /// Subtracts unscaled coordinates with overflow wrapping.
    @inline(always) @_transparent
    static func &- (lhs: Self, rhs: Self) -> Self {
      .init(x: lhs.x &- rhs.x, y: lhs.y &- rhs.y)
    }
  }
}

extension SwiftTrueTypeInterpreter.FixedCartesian {
  /// Calculates the magnitude (length) of the vector.
  ///
  /// - Parameter rule: Rounding rule to apply
  /// - Returns: Magnitude of the vector
  @inline(always) @_transparent
  public func magnitude(rounding rule: RoundingRule = .towardZero) -> Fixed {
    // Compat: reference interpreter promotes to double then casts back (rounding toward zero)
    let dist = hypot(Double(x), Double(y))
    // `dist` is non-negative; saturate to `.max` when it exceeds the representable range.
    return .init(ifRepresentable: dist, rounding: rule) ?? .max
  }

  /// Computes the dot product with another vector.
  ///
  /// - Parameter other: Vector to compute dot product with
  /// - Returns: Dot product of the two vectors
  @inline(always) @_transparent
  public func dot(_ other: Self) -> Fixed {
    other.x &* self.x &+ other.y &* self.y
  }
}

extension SwiftTrueTypeInterpreter.OutlineCoord {
  /// Creates an outline coordinate from an unscaled coordinate using bit patterns.
  ///
  /// Bincompat: Note that this effectively divides the unscaled value by 64!
  /// This is compatible with the reference, but it seems likely that this behaviour was not intentional.
  ///
  /// - Parameter coord: Unscaled coordinate to convert
  @inline(always) @_transparent
  init(bitPattern coord: SwiftTrueTypeInterpreter.UnscaledCoord) {
    self.init(
      x: .init(bitPattern: .init(coord.x)),
      y: .init(bitPattern: .init(coord.y))
    )
  }

  /// Subtracts two outline coordinates with overflow wrapping.
  ///
  /// - Parameters:
  ///   - lhs: Left coordinate
  ///   - rhs: Right coordinate
  /// - Returns: Difference coordinate
  @inline(always) @_transparent
  static func &- (lhs: Self, rhs: Self) -> Self {
    Self(x: lhs.x &- rhs.x, y: lhs.y &- rhs.y)
  }

  /// Adds a vector to an outline coordinate.
  ///
  /// - Parameters:
  ///   - lhs: Outline coordinate
  ///   - rhs: Vector to add
  /// - Returns: Sum as outline coordinate
  @inline(always) @_transparent
  static func &+ (
    lhs: Self,
    rhs: SwiftTrueTypeInterpreter.FixedVector<SwiftTrueTypeInterpreter.F26Dot6>
  ) -> Self {
    Self(x: lhs.x &+ rhs.x, y: lhs.y &+ rhs.y)
  }

  /// Adds a distance vector with overflow detection.
  ///
  /// - Parameter other: Distance vector to add
  /// - Returns: Tuple of result coordinate and overflow flag
  @inline(always) @_transparent
  func addingReportingOverflow(_ other: Distance) -> (Self, Bool) {
    let x = x.addingReportingOverflow(other.x)
    let y = y.addingReportingOverflow(other.y)
    return (.init(x: x.partialValue, y: y.partialValue), x.overflow || y.overflow)
  }

  /// Divides coordinate by `divisor`.
  ///
  /// - Parameters:
  ///   - divisor: Vector to divide by
  ///   - rule: Rounding rule to apply
  /// - Returns: Vector result of division
  @inline(always) @_transparent
  func div(
    _ divisor: SwiftTrueTypeInterpreter.FixedVector<SwiftTrueTypeInterpreter.F16Dot16>,
    rounding rule: RoundingRule = SwiftTrueTypeInterpreter.F26Dot6.defaultRounding
  ) -> SwiftTrueTypeInterpreter.FixedVector<SwiftTrueTypeInterpreter.F26Dot6> {
    .init(x: self.x.div(divisor.x, rounding: rule), y: self.y.div(divisor.y, rounding: rule))
  }
}

// MARK: Mixed-point arithmetic with reference-accurate rounding

extension SwiftTrueTypeInterpreter.FixedVector where Fixed == SwiftTrueTypeInterpreter.F26Dot6 {
  /// Normalizes vector using legacy fnt_Normalize algorithm for compatibility.
  ///
  /// This method faithfully reimplements the reference interpreter's normalization
  /// algorithm to maintain exact behavioral compatibility, including handling of
  /// edge cases and specific rounding behaviors.
  ///
  /// - Returns: Normalized F2Dot14 vector
  @inline(always) @_transparent  // Only one callsite
  public func normalizeLikeFnt_NormalizeUsedTo()
  -> SwiftTrueTypeInterpreter.FixedVector<SwiftTrueTypeInterpreter.F2Dot14> {
    // Reimplement the fnt_Normalize algorithm faithfully.
    // The original comment was:
    /*
     *	Since x and y are 26.6, and currently that means they are really 16.6,
     *	when treated as Fract, they are 0.[8]22, so shift up to 0.30 for accuracy
     */
    // glyf coordinates are expressed as 16-bit signed integer (aka: FUnit)
    // values. Since scaled hinted points were expressed as F26Dot6 the
    // reference interpreter assumed the 10 MSB would always be zero.
    // When you take a 26.6 value assumed to be 16.6 in terms of
    // meaningfulness and express it as a 2.30 Fract value, what you have
    // are 2 integral bits "known" to be zero, followed by 8 fractional bits
    // "known" to be zero, followed by 22 bits that you care about.
    // "Accuracy" refers to shifting the values to be near 1.0, where
    // floating-point math is most accurate. Because the floating-point
    // operations are normalization, this left shift cancels itself out;
    // we don't need any compensating right shift later.

    let largestAbs = max(absWithSaturation(x), absWithSaturation(y))
    let shift = largestAbs.bitPattern.leadingZeroBitCount - 2

    guard shift >= 0 else {
      // Left shift by a negative number was Undefined Behavior in C.
      // When unit-tested, the C code resolved these cases to one of
      // these: (0, 16384), (16384, 0), or (27969, 27969). Among these
      // equally arbitrary values, we choose (16384, 0) since that is
      // also the value returned when the magnitude is rounded down to 0
      // (e.g. normalizing from one point to itself.)
      return .init(x: 1, y: 0)
    }

    let x1 = Fixed.IntegerType(truncatingIfNeeded: x.bitPattern << shift)
    let y1 = Fixed.IntegerType(truncatingIfNeeded: y.bitPattern << shift)
    let dx1 = Double(x1)
    let xx1 = dx1 * dx1
    let dy1 = Double(y1)
    let yy1 = dy1 * dy1
    // After the leading-zero shift above, the larger of |x1| and |y1| has its top bit
    // at position 29, so |x1|, |y1| < 2^30 and sqrt(x1*x1 + y1*y1) < 2^30 * sqrt(2)
    // < 2^31 — `Int32(exactly:)` cannot fail.
    let magnitude = Int32(sqrt(xx1 + yy1).rounded(.down))

    guard magnitude != 0 else {
      return .init(x: 1, y: 0)
    }

    // Compat: replicates reference interpreter's behaviour when dividing 2.30 numerics.
    let kFractOne: Double = .init(SwiftTrueTypeInterpreter.F2Dot30(1).bitPattern)
    let divisor: Double = .init(magnitude) / kFractOne
    let dividendX: Double = .init(x1) / kFractOne
    let dividendY: Double = .init(y1) / kFractOne
    let quotientX = dividendX / divisor
    let quotientY = dividendY / divisor
    let divX: Int32 = .init(quotientX * kFractOne)
    let divY: Int32 = .init(quotientY * kFractOne)

    let truncX = divX.shifted(rightBy: UInt16.bitWidth, rounding: .toNearestOrUp)
    let truncY = divY.shifted(rightBy: UInt16.bitWidth, rounding: .toNearestOrUp)

    let vecX = SwiftTrueTypeInterpreter.F2Dot14(bitPattern: Int16(truncatingIfNeeded: truncX))
    let vecY = SwiftTrueTypeInterpreter.F2Dot14(bitPattern: Int16(truncatingIfNeeded: truncY))

    return .init(x: vecX, y: vecY)
  }
}

// The below extensions are passthroughs to arithmetic functions defined in Math.swift
// Their concreteness is required (vs a protocol-based approach) to guarantee the operators' specialization.

extension SwiftTrueTypeInterpreter.FixedCartesian where Fixed == SwiftTrueTypeInterpreter.F2Dot14 {
  /// Computes mixed-precision dot product with F26Dot6 vector.
  ///
  /// - Parameter other: F26Dot6 vector to compute dot product with
  /// - Returns: Dot product result in F26Dot6 format
  @inline(always) @_transparent
  func dot<Other: SwiftTrueTypeInterpreter.FixedCartesian & ~Copyable & ~Escapable>(_ other: borrowing Other) -> Other.Fixed
  where Other.Fixed == SwiftTrueTypeInterpreter.F26Dot6 {
    other.x.mixedMulRoundingToNearestOrAway(self.x) &+ other.y.mixedMulRoundingToNearestOrAway(self.y)
  }
}

extension SwiftTrueTypeInterpreter.FixedVector where Fixed == SwiftTrueTypeInterpreter.F26Dot6 {
  /// Creates vector by scaling a value with an F2Dot14 vector.
  ///
  /// - Parameters:
  ///   - value: Scalar value to scale
  ///   - vector: F2Dot14 vector to scale by
  @inline(always) @_transparent
  init(
    scaling value: Fixed,
    by vector: SwiftTrueTypeInterpreter.FixedVector<SwiftTrueTypeInterpreter.F2Dot14>
  ) {
    self.x = value.mixedMulRoundingToNearestOrAway(vector.x)
    self.y = value.mixedMulRoundingToNearestOrAway(vector.y)
  }
}

extension SwiftTrueTypeInterpreter.FixedVector where Fixed == SwiftTrueTypeInterpreter.F16Dot16 {
  /// Multiplies F16Dot16 vector by F2Dot14 vector with reference-accurate rounding.
  ///
  /// - Parameter other: F2Dot14 vector to multiply by
  /// - Returns: Product vector in F16Dot16 format
  @inline(always) @_transparent
  func mixedMulRoundingToNearestOrAway(
    _ other: SwiftTrueTypeInterpreter.FixedVector<SwiftTrueTypeInterpreter.F2Dot14>
  ) -> Self {
    .init(x: self.x.mixedMulRoundingToNearestOrAway(other.x), y: self.y.mixedMulRoundingToNearestOrAway(other.y))
  }
}

extension SwiftTrueTypeInterpreter.OutlineCoord {
  /// Creates outline coordinate by scaling a value with an F2Dot14 vector.
  ///
  /// - Parameters:
  ///   - value: Scalar value to scale
  ///   - vector: F2Dot14 vector to scale by
  @inline(always) @_transparent
  init(
    scaling value: Fixed,
    by vector: SwiftTrueTypeInterpreter.FixedVector<SwiftTrueTypeInterpreter.F2Dot14>
  ) {
    self.x = value.mixedMulRoundingToNearestOrAway(vector.x)
    self.y = value.mixedMulRoundingToNearestOrAway(vector.y)
  }

  /// Multiplies coordinate by F16Dot16 vector with reference-accurate rounding.
  ///
  /// - Parameter other: F16Dot16 vector to multiply by
  /// - Returns: Product vector
  @inline(always) @_transparent
  func mixedMulRoundingToNearestOrUp(
    _ other: SwiftTrueTypeInterpreter.FixedVector<SwiftTrueTypeInterpreter.F16Dot16>
  ) -> SwiftTrueTypeInterpreter.FixedVector<Fixed> {
    .init(x: self.x.mixedMulRoundingToNearestOrUp(other.x), y: self.y.mixedMulRoundingToNearestOrUp(other.y))
  }
}

extension SwiftTrueTypeInterpreter.FixedCoord: Sendable where Fixed: Sendable {}
extension SwiftTrueTypeInterpreter.FixedVector: Sendable where Fixed: Sendable {}
