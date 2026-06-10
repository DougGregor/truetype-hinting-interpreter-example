/// Infix operator for division with saturation.
infix operator &/ : MultiplicationPrecedence

extension FixedPoint {
  /// Performs division with saturation using the &/ operator.
  ///
  /// - Parameters:
  ///   - a: Dividend value
  ///   - b: Divisor value
  /// - Returns: Result of division with saturation applied
  @_transparent
  public static func &/ (a: Self, b: Self) -> Self {
    a.dividedWithSaturation(by: b)
  }
}

// MARK: Mixed-point arithmetic with reference-accurate rounding

extension FixedPoint {
  /// Robust full-width multiply and divide operation with rounding.
  ///
  /// This function is a variation of `scaledIfRepresentable(by:rounding:)` that never fails,
  /// handling division by zero by returning `.min` or `.max` based on the signedness of the product.
  @_transparent
  public func mulDiv<Fixed: FixedPoint>(
    _ b: Fixed,
    _ c: Fixed,
    rounding rule: RoundingRule
  ) -> Self {
    guard let product = self.scaledIfRepresentable(by: (numerator: b, denominator: c), rounding: rule) else {
      // A precision-preserving saturating variant would let us skip the Double fallback, but this is a cold path.
      if c != 0 {
        return .init(clamping: Double(self) * Double(b) / Double(c))
      }
      return (self >= 0) != (b >= 0) ? Self.min : Self.max
    }
    return product
  }
}

extension FixedPoint {
  /*
   * MARK: Optimized mixed-point multiplication
   *
   * TrueType hinting involves a number of "mixed-point" arithmetic operations, which the reference interpreter
   * implemented differently depending (mostly) on the types involved. This resulted in multiple different rounding
   * behaviours.
   *
   * This could be accomplished using `self.scaledIfRepresentable(by: (numerator: other, denominator: 1),
   * rounding: rule)`, but the compiler is not able to optimize that implementation to the same degree as the
   * implementations below.
   */

  /// Multiplies by another fixed-point value with "nearest or away from zero" rounding.
  ///
  /// Performs mixed-point arithmetic multiplication with reference-accurate rounding behavior.
  /// Uses "ties away from zero" rounding where halfway cases round away from zero.
  /// Optimized implementation that handles saturation on overflow.
  ///
  /// - Parameter other: Fixed-point value to multiply by
  /// - Returns: Product rounded to nearest or away from zero
  @inline(always) @_transparent
  func mixedMulRoundingToNearestOrAway<Other: FixedPoint>(_ other: Other) -> Self {
    assert(
      Self.IntegerType.bitWidth <= Int32.bitWidth && Other.IntegerType.bitWidth <= Int32.bitWidth,
      "This function does not handle multiplication overflow properly for types with more than 32 bits"
    )
    if other == 1 { return self }

    let divisor: Int64 = 1 << Other.fractionBits
    let half: Int64 = divisor >> 1

    // Full-precision product
    let product = Int64(self.bitPattern) * Int64(other.bitPattern)

    // 1. quotient rounded toward zero
    // (`>>` floors negative values; `/` truncates to zero.)
    let truncated: Int64 = product / divisor

    // 2. positive remainder
    let remainder = abs(product) % divisor

    // 3. “nearest, ties away from 0”
    var rounded = truncated
    if remainder >= half {  // > ½  or  tie
      rounded += (product >= 0) ? 1 : -1
    }

    // 4. saturate to 26.6 range on overflow
    if rounded > Self.IntegerType.max { return .init(bitPattern: .max) }
    if rounded < Self.IntegerType.min { return .init(bitPattern: .min) }

    return .init(bitPattern: .init(truncatingIfNeeded: rounded))
  }

  /// Multiplies by another fixed-point value with "nearest or up" rounding.
  ///
  /// Performs mixed-point arithmetic multiplication with reference-accurate rounding behavior.
  /// Uses "ties toward positive infinity" rounding where halfway cases round up (toward +∞).
  /// Optimized implementation that handles saturation on overflow.
  ///
  /// - Parameter other: Fixed-point value to multiply by
  /// - Returns: Product rounded to nearest or up
  @inline(always) @_transparent
  func mixedMulRoundingToNearestOrUp<Other: FixedPoint>(_ other: Other) -> Self {
    if other == 1 { return self }

    // Full-precision product
    let product = Int64(self.bitPattern) * Int64(other.bitPattern)

    let divisor: Int64 = 1 << Other.fractionBits
    let half: Int64 = divisor >> 1

    // 1. quotient rounded toward zero
    // (`>>` floors negative values; `/` truncates to zero.)
    let truncated: Int64 = product / divisor

    // 2. positive remainder
    let remainder = abs(product) % divisor

    // 3. round to nearest or up rounding
    var rounded = truncated
    if remainder > half {
      rounded += (product >= 0) ? 1 : -1
    } else if remainder == half {
      if product >= 0 {
        rounded += 1
      }
      // else `/` already rounded up (toward zero)
    }

    // 4. saturate on overflow
    if rounded > Self.IntegerType.max { return .init(bitPattern: .max) }
    if rounded < Self.IntegerType.min { return .init(bitPattern: .min) }

    return .init(bitPattern: .init(truncatingIfNeeded: rounded))
  }
}

extension SwiftTrueTypeInterpreter.F26Dot6 {
  /// Divides this F26Dot6 value by an F16Dot16 value.
  ///
  /// - Parameters:
  ///   - other: F16Dot16 divisor value
  ///   - rule: Rounding rule to apply (defaults to .toNearestOrUp)
  /// - Returns: Division result as F26Dot6
  @inline(always) @_transparent
  func div(
    _ other: SwiftTrueTypeInterpreter.F16Dot16,
    rounding rule: RoundingRule = .toNearestOrUp
  ) -> Self {
    self.mulDiv(1, other, rounding: rule)
  }
}
