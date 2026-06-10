// This amalgamated source file is vendored from the Swift Numerics project
//
//  All appearance of the word "public" are commented out
//  Any other changes from the original are marked with // BEGIN CHANGE // END CHANGE

// ===--- AdditiveArithmetic.swift -----------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

extension FixedPoint {
  @_transparent
  public static var zero: Self {
    Self(bitPattern: .zero)
  }

  @_transparent
  public static func + (a: Self, b: Self) -> Self {
    Self(bitPattern: a.bitPattern + b.bitPattern)
  }

  @_transparent
  public static func - (a: Self, b: Self) -> Self {
    Self(bitPattern: a.bitPattern - b.bitPattern)
  }

  @_transparent
  public static prefix func - (a: Self) -> Self {
    zero - a
  }
}

extension FixedPoint {
  @_transparent
  public static func &+ (a: Self, b: Self) -> Self {
    Self(bitPattern: a.bitPattern &+ b.bitPattern)
  }

  @_transparent
  public static func &- (a: Self, b: Self) -> Self {
    Self(bitPattern: a.bitPattern &- b.bitPattern)
  }

  @_transparent
  public static func &+= (a: inout Self, b: Self) {
    a.bitPattern &+= b.bitPattern
  }

  @_transparent
  public static func &-= (a: inout Self, b: Self) {
    a.bitPattern &-= b.bitPattern
  }
}

/// The [absolute value](https://en.wikipedia.org/wiki/Absolute_value)
/// of this number.
///
/// > Note:
/// > If the type is signed and the argument is `.min`, then the absolute
/// > value is not representable, and a precondition failure will occur.
/// >
/// > To avoid this, you may want to use the `.magnitude` property instead,
/// > which is always representable.
/// >
/// > You could also consider using ``absWithSaturation(_:)``, which returns
/// > `.max` if the absolute value would overflow.
@_transparent
public func abs<T: FixedPoint>(_ a: T) -> T {
  a.bitPattern < .zero ? -a : a
}

/// The [absolute value](https://en.wikipedia.org/wiki/Absolute_value)
/// of this number if it is representable, otherwise `.max`.
///
/// If the type is signed and the argument is `.min`, then ``abs(_:)`` is
/// not representable and a precondition failure occurs.
///
/// The `absWithSaturation(_:)` function avoids this by saturating to `.max`
/// instead of overflowing. You might also consider using the `.magnitude`
/// property, which is always representable.
/*@inlinable*/
public func absWithSaturation<T: FixedPoint>(_ a: T) -> T {
  a.bitPattern < 0 ? .zero.subtractingWithSaturation(a) : a
}

// ===--- FixedPoint.swift -------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

/// A binary [fixed-point][fixed] arithmetic type.
///
/// A fixed-point type is represented by an integer, but we consider a _fixed_
/// subset of the bits to be fractional. For example, we might define an eight
/// bit signed type with three fractional bits. We can do this with a minimal
/// amount bit of boilerplate:
///
/// ```swift
/// @frozen struct Int8Q3: FixedPoint {
///   // An eight-bit signed type ...
///   public var bitPattern: Int8
///
///   // ... with three fractional bits
///   public static var fractionBits: Int { 3 }
///
///   // If we want, we can customize the rounding policy of the *, &*, /
///   // operators (otherwise, it defaults to .toNearestOrUp)
///   public static var defaultRounding: RoundingRule { .toNearestOrEven }
///
///   // The only other thing we need to do is to define
///   // how we construct one from its bit pattern.
///   public init(bitPattern: Int8) {
///     self.bitPattern = bitPattern
///   }
/// }
/// ```
/// `Int8` can represent integers between `-128` and `127`; because we have
/// three fractional bits, our `Int8Q3` type represents all multiples of 1/8
/// between `-16` (`-0b10000.000`) and `15.875` (`0b01111.111`).
///
/// Addition and subtraction of fixed-point numbers is just addition or
/// subtraction of the underlying bit patterns:
/// ```swift
///                          // bit pattern
/// let a: Int8Q3 = 1.125    // 0b00001.001
/// let b: Int8Q3 = 2.5      // 0b00010.100
/// let c: Int8Q3 = a + b    // 0b00011.101 (3.625)
/// ```
/// Just like integer arithmetic, addition and subtraction trap on overflow,
/// but wrapping operations are provided as `&+` and `&-`:
/// ```swift
///                          // bit pattern
/// let a: Int8Q3 = 15.125   // 0b01111.001
/// let b: Int8Q3 = 1.5      // 0b00001.100
/// let c: Int8Q3 = a + b    //   [trap]
/// let d: Int8Q3 = a &+ b   // 0b10000.101 (-15.375)
/// ```
///
/// [fixed]: https://en.wikipedia.org/wiki/Fixed-point_arithmetic
// BEGIN CHANGE
public protocol FixedPoint:
// END CHANGE
  AdditiveArithmetic,
  ExpressibleByIntegerLiteral,
  ExpressibleByFloatLiteral,
  Comparable,
  Hashable,
  LosslessStringConvertible,
  Numeric
where Magnitude: FixedPoint,
      Magnitude.IntegerType: UnsignedInteger,
      Magnitude.Magnitude == Magnitude {
  /// The underlying `FixedWidthInteger` type used to represent values of
  /// this type.
  ///
  /// If IntegerType is signed, then this type is signed. If IntegerType
  /// is unsigned, then this type is unsigned.
  associatedtype IntegerType: FixedWidthInteger

  /// The number of bits in the representation that have fractional weight.
  ///
  /// For instance, a fixed-point type capable of representing multiples of
  /// 1/8 would have `fractionBits = 3`.
  ///
  /// - Precondition: this value must be greater than zero, and less than
  ///   or equal to the number of value bits in
  ///   ``/FixedPointModule/FixedPoint/IntegerType``.
  static var fractionBits: Int { get }

  /// The rounding rule to use with the `*`, `&*`, and `/` operators.
  ///
  /// > Note:
  /// If you do not specify a `defaultRounding` rule when defining a
  /// FixedPoint type, it will default to `.toNearestOrUp`.
  static var defaultRounding: RoundingRule { get }

  /// The integer representation underlying this fixed-point value.
  ///
  /// For example, if we have a signed eight-bit fixed-point type with
  /// three fraction bits named `Int8Q3`, then:
  /// ```
  /// let fixed: Int8Q3 = 2
  /// let bits = fixed.bitPattern // 0b00010_000 = 16 as Int8
  /// ```
  var bitPattern: IntegerType { get set }

  /// Create a fixed-point value from an integer bitPattern.
  init(bitPattern: IntegerType)
}

extension FixedPoint {
  /// Validate the invariants on fractionBits; this is a type-level property,
  /// but we can't encode the requirements in the type system. Instead we
  /// enforce them as an assert in initializers so that they are checked
  /// (redundantly) in debug builds but should be eliminated in release.
  @_transparent
  static func invariantCheck() {
    if IntegerType.isSigned {
      assert(fractionBits > 0 && fractionBits < IntegerType.bitWidth)
    } else {
      assert(fractionBits > 0 && fractionBits <= IntegerType.bitWidth)
    }
  }

  /// Mask to select the ones bit in `bitPattern`.
  ///
  /// If `IntegerType` is signed and `fractionBits` is `IntegerType.bitWidth-1`,
  /// then there is—strictly speaking—no ones bit and `unit` identifies the sign
  /// bit. Similarly, if `IntegerType` is unsigned and `fractionBits` is
  /// `IntegerType.bitWidth`, then there is no ones bit and `unit` is zero.

  public static var unit: IntegerType {
    1 << fractionBits
  }

  /// Mask to select the ½ bit in `bitPattern`.
  ///
  /// Unlike `unit`, this bit always exists, and is never a signbit.

  public static var half: IntegerType {
    1 << (fractionBits - 1)
  }

  /// Mask to select the fractional bits in `bitPattern`.

  public static var fractionMask: IntegerType { unit &- 1 }

  /// Mask to select the integral bits (including sign bit) in `bitPattern`.

  public static var integralMask: IntegerType { 0 &- unit }

  /// The number of bits used to represent the integeral part of the type.

  public static var integralBits: Int { IntegerType.bitWidth - fractionBits }

  /// A string describing the type, e.g. "signed 26.6"
  @inline(never)
  public static var name: String {
    "\(IntegerType.isSigned ? "" : "un")signed \(integralBits).\(fractionBits)"
  }
}

extension FixedPoint {
  @_transparent
  public static func == (a: Self, b: Self) -> Bool {
    a.bitPattern == b.bitPattern
  }

  @_transparent
  public static func < (a: Self, b: Self) -> Bool {
    a.bitPattern < b.bitPattern
  }

  /// The minimum representable number in this type.
  @_transparent
  public static var min: Self {
    Self(bitPattern: .min)
  }

  /// The maximum representable number in this type.
  @_transparent
  public static var max: Self {
    Self(bitPattern: .max)
  }

  @_transparent
  public var integralPart: IntegerType {
    bitPattern >> Self.fractionBits
  }
}

// ===--- FloatingPoint.swift ----------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

extension BinaryFloatingPoint {
  /*@inlinable*/
  public init<Fixed: FixedPoint>(_ other: Fixed) {
    // TODO: make this work for cases where other.bitPattern overflows Self
    // even though the actual value of other is in-range.
    self.init(
      sign: .plus,
      exponent: Self.Exponent(-Fixed.fractionBits),
      significand: Self(other.bitPattern)
    )
  }
}

// ===--- Initializers.swift -----------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

// MARK: ExpressibleByFloatLiteral
extension FixedPoint {
  /*@inlinable*/
  public init(floatLiteral value: Double) {
    Self.invariantCheck()
    self.init(value, rounding: .toNearestOrEven)
  }
}

// MARK: - Inits from other FixedPoint formats
extension FixedPoint {
  /*@inlinable*/
  public init<Other: FixedPoint>(
    _ other: Other,
    rounding rule: RoundingRule = .toNearestOrUp
  ) {
    Self.invariantCheck()
    let shift = Other.fractionBits - Self.fractionBits
    if Other.IntegerType.bitWidth > Self.IntegerType.bitWidth {
      self.init(bitPattern: IntegerType(
        other.bitPattern.shifted(rightBy: shift, rounding: rule)
      ))
    } else {
      self.init(bitPattern: IntegerType(other.bitPattern).shifted(
        rightBy: shift, rounding: rule
      ))
    }
  }
}

// MARK: - Inits from BinaryFloatingPoint

extension FixedPoint {
  /// The specified floating-point `value` rounded to a representable
  /// fixed-point number according to `rule`.
  ///
  /// For example, suppose we have a signed eight-bit FixedPoint format
  /// with three fraction bits:
  /// ```
  /// struct Int8Q3: FixedPoint {
  ///   public var bitPattern: Int8
  ///   public static var fractionBits: Int { 3 }
  ///   public init(bitPattern: Int8) {
  ///     self.bitPattern = bitPattern
  ///   }
  /// }
  /// ```
  /// and suppose we initialize it from the Float value `1.2`, rounding down:
  /// ```
  /// let float: Float = 1.2
  /// let fixed = Int8Q3(float, rounding: .down)
  /// ```
  /// the two closest representable values are `1.125` (bitPattern
  /// `0b00001.001`) and `1.25` (bitPattern `0b00001.010`). Because we
  /// specified rounding _down_, the smaller of the two is chosen, and the
  /// result is `1.125`.
  ///
  /// If, after rounding, the value would be outside the range representable
  /// in the fixed-point type, a precondition failure occurs. Thus:
  /// ```
  /// // rounds to 15.875, which is Int8Q3.max
  /// let fine = Int8Q3(15.9, rounding: .down)
  /// // would round to 16.0, which is not representable
  /// let trap = Int8Q3(15.94, rounding: .toNearestOrUp)
  /// ```
  ///
  /// > See also:
  /// If you need to avoid trapping on out-of-range values, consider using
  /// ``init(clamping:rounding:)`` or ``init(ifRepresentable:rounding:)``
  /*@inlinable*/
  public init<Other: BinaryFloatingPoint>(
    _ value: Other,
    rounding rule: RoundingRule = .toNearestOrEven
  ) {
    self = Self(ifRepresentable: value, rounding: rule)!
  }

  /// The specified floating-point `value` rounded to a representable
  /// fixed-point number according to `rule`, and clamping any out-of-range
  /// values to the representable range.
  ///
  /// If `init(value, rounding:rule)` succeeds, then
  /// `init(clamping:value, rounding:rule)` produces the same result.
  /// However, if value is not in the representable range of the fixed-point
  /// format after rounding, the first init will have a precondition failure,
  /// while the `clamping:` init will return `.max` (if value is positive)
  /// or `.min` (if it is not).
  ///
  /// > See also:
  /// ``/FixedPoint/init(_:rounding:)-67pr9`` and ``init(ifRepresentable:rounding:)``
  /*@inlinable*/
  public init<Other: BinaryFloatingPoint>(
    clamping value: Other,
    rounding rule: RoundingRule = .toNearestOrEven
  ) {
    if let fixed = Self(ifRepresentable: value, rounding: rule) {
      self = fixed
    } else {
      self.init(bitPattern: value > 0 ? .max : .min)
    }
  }

  /// The specified floating-point `value` rounded to a representable
  /// fixed-point number according to `rule`, returning `nil` if the value
  /// is out-of-range after rounding.
  ///
  /// If `init(value, rounding:rule)` succeeds, then
  /// `init(ifRepresentable:value, rounding:rule)` produces the same result.
  /// However, if value is not in the representable range of the fixed-point
  /// format after rounding, the first init will have a precondition failure,
  /// while the `ifRepresentable:` init will return `nil`.
  ///
  /// > See also:
  /// ``/FixedPoint/init(_:rounding:)-67pr9`` and ``init(clamping:rounding:)``
  /*@inlinable*/
  public init?<Other: BinaryFloatingPoint>(
    ifRepresentable value: Other,
    rounding rule: RoundingRule = .toNearestOrEven
  ) {
    Self.invariantCheck()
    let scale = Other(
      sign: .plus,
      exponent: Other.Exponent(Self.fractionBits),
      significand: 1
    )
    let rounded = (scale * value).rounding(rule)
    guard let maybeBitPattern = IntegerType(exactly: rounded) else {
      return nil
    }
    self.init(bitPattern: maybeBitPattern)
  }
}

// ===--- Integers.swift ---------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

// MARK: ExpressibleByIntegerLiteral
extension FixedPoint {
  /*@inlinable*/
  public init(integerLiteral value: IntegerType.IntegerLiteralType) {
    Self.invariantCheck()
    let unscaledInteger = IntegerType(integerLiteral: value)
    // If unit is zero, there are only fraction bits, and therefore the
    // only representable integral value is zero.
    precondition(
      Self.unit != 0 || unscaledInteger == 0,
      "\(value) cannot be represented in \(Self.name)."
    )
    self = Self(bitPattern: unscaledInteger * Self.unit)
  }
}

// MARK: - Inits from BinaryInteger
extension FixedPoint {
  /*@inlinable*/
  public init?<Other: BinaryInteger>(exactly other: Other) {
    Self.invariantCheck()
    guard let unscaledInteger = IntegerType(exactly: other) else {
      return nil
    }
    guard Self.unit != 0 || unscaledInteger == 0 else { return nil }
    self = Self(bitPattern: unscaledInteger * Self.unit)
  }

  /*@inlinable*/
  public init<Other: BinaryInteger>(_ other: Other) {
    Self.invariantCheck()
    // This might trap, but if it does, we would have trapped anyway.
    let unscaledInteger = IntegerType(other)
    // If unit is zero, there are only fraction bits, and therefore the
    // only representable integral value is zero.
    precondition(
      Self.unit != 0 || unscaledInteger == 0,
      "\(other) cannot be represented in \(Self.name)."
    )
    self = Self(bitPattern: unscaledInteger * Self.unit)
  }
}

// ===--- Magnitude.swift -------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

/// The Magnitude of a signed FixedPoint type.
///
/// This is an unsigned FixedPoint type whose IntegerType is the magnitude
/// of Wrapped.IntegerType, and which has the same number of fractionalBits
/// as Wrapped.
// BEGIN CHANGE
/*@frozen*/
// END CHANGE
public struct FixedPointMagnitude<Wrapped>: FixedPoint where Wrapped: FixedPoint {
  public typealias Magnitude = Self

  public var bitPattern: Wrapped.IntegerType.Magnitude

  @_transparent public static var fractionBits: Int {
    Wrapped.fractionBits
  }

  @_transparent public static var defaultRounding: RoundingRule {
    Wrapped.defaultRounding
  }

  @_transparent public init(bitPattern: Wrapped.IntegerType.Magnitude) {
    self.bitPattern = bitPattern
  }
}

// ===--- Numeric.swift ----------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

extension FixedPoint where IntegerType: SignedInteger {
  public typealias Magnitude = FixedPointMagnitude<Self>

  @_transparent
  public var magnitude: FixedPointMagnitude<Self> {
    FixedPointMagnitude(bitPattern: bitPattern.magnitude)
  }
}

extension FixedPoint where IntegerType: UnsignedInteger {
  public typealias Magnitude = Self

  @_transparent
  public var magnitude: Self { self }
}

extension FixedPoint {
  @_transparent
  public func multipliedReportingOverflow(
    by other: Self,
    rounding rule: RoundingRule = Self.defaultRounding
  ) -> (wrappedValue: Self, overflow: Bool) {
    var prod = bitPattern.multipliedFullWidth(by: other.bitPattern)
    func roundViaAddition(_ addend: IntegerType.Magnitude) {
      let (low, carry) = prod.low.addingReportingOverflow(addend)
      let high = prod.high &+ (carry ? 1 : 0)
      prod = (high, low)
    }

    let frac = IntegerType.Magnitude(truncatingIfNeeded: Self.fractionMask)
    let unit = IntegerType.Magnitude(truncatingIfNeeded: Self.unit)
    let half = IntegerType.Magnitude(truncatingIfNeeded: Self.half)
    let sign = IntegerType.Magnitude(truncatingIfNeeded: prod.high.signbit)

    switch rule {
    case .down: break
    case .up:
      roundViaAddition(frac)
    case .towardZero:
      roundViaAddition(frac & sign)
    case .awayFromZero:
      roundViaAddition(frac & ~sign)
    case .toOdd:
      if Self.fractionBits == IntegerType.bitWidth {
        prod.high |= prod.low == 0 ? 0 : 1
      } else {
        prod.low |= (prod.low &+ frac) & unit
      }
    case .toNearestOrDown:
      roundViaAddition(half &- 1)
    case .toNearestOrUp:
      roundViaAddition(half)
    case .toNearestOrZero:
      roundViaAddition(half &- 1 &- sign)
    case .toNearestOrAway:
      roundViaAddition(half &+ sign)
    case .toNearestOrEven:
      let parity: IntegerType.Magnitude
      if Self.fractionBits == IntegerType.bitWidth {
        parity = IntegerType.Magnitude(truncatingIfNeeded: prod.high) & 1
      } else {
        parity = prod.low >> Self.fractionBits & 1
      }
      roundViaAddition(half &- 1 &+ parity)
    case .stochastically:
      roundViaAddition(.random(in: 0 ... frac))
    case .requireExact:
      guard prod.low & frac == 0 else {
        preconditionFailure("Multiplication is not exact.")
      }
    }
    let bitsFromLo = IntegerType(truncatingIfNeeded: prod.low >> Self.fractionBits)
    let bitsFromHi = prod.high &<< Self.integralBits
    let lostBits = prod.high >> (Self.fractionBits - (IntegerType.isSigned ? 1 : 0))
    let overflow = lostBits != prod.high.signbit
    return (Self(bitPattern: bitsFromHi | bitsFromLo), overflow)
  }

  @_transparent
  public static func * (a: Self, b: Self) -> Self {
    guard case let (result, false) = a.multipliedReportingOverflow(by: b) else {
      preconditionFailure("Multiplication \(a)*\(b) overflows.")
    }
    return result
  }

  @_transparent
  public static func *= (a: inout Self, b: Self) {
    a = a * b
  }

  @_transparent
  public static func &* (a: Self, b: Self) -> Self {
    a.multipliedReportingOverflow(by: b).wrappedValue
  }

  /// The quotient produced dividing this value by `other`, rounding according
  /// to the specified `rule`, if it is representable.
  ///
  /// If the result is not representable, because one of the following criteria
  /// hold:
  /// - the divisor is zero
  /// - the quotient would overflow
  /// - the quotient is not exact and the rounding rule is `.requireExact`
  /// then the result is `nil`.
  /*@inlinable*/
  public func dividedIfRepresentable(
    by other: Self,
    rounding rule: RoundingRule = Self.defaultRounding
  ) -> Self? {
    let hi = bitPattern &>> Self.integralBits
    let lo = IntegerType.Magnitude(truncatingIfNeeded: bitPattern) << Self.fractionBits
    if let quotient = other.bitPattern.dividing((hi, lo), rounding: rule) {
      return Self(bitPattern: quotient)
    }
    return nil
  }

  @_transparent
  public static func / (a: Self, b: Self) -> Self {
    guard let result = a.dividedIfRepresentable(by: b) else {
      preconditionFailure("Division \(a)/\(b) overflows.")
    }
    return result
  }
}

extension FixedPoint {
  /// `self * ratio`, rounded according to `rule` if that value is
  /// representable without overflow.
  ///
  /// If the result would overflow, `nil` is returned. Underflow rounds
  /// to either zero or ±leastMagnitude without reporting an error.
  @_transparent
  public func scaledIfRepresentable<Other: FixedPoint>(
    by ratio: (numerator: Other, denominator: Other),
    rounding rule: RoundingRule = Self.defaultRounding
  ) -> Self? {
    bitPattern.multiplied(
      by: ratio.numerator.bitPattern,
      dividedBy: ratio.denominator.bitPattern,
      rounding: rule
    ).map { Self(bitPattern: $0) }
  }
}

// ===--- OverflowArithmetic.swift -----------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

extension FixedPoint {
  /// Fixed-point addition reporting overflow.
  ///
  /// If no overflow occurs, `partialValue` is `self + other` and `overflow`
  /// is false. If `self + other` would overflow, `partialValue` holds the
  /// wrapped result, and `overflow` is true.
// BEGIN CHANGE
   @inline(always)
// END CHANGE
  public func addingReportingOverflow(_ other: Self) -> (
    partialValue: Self,
    overflow: Bool
  ) {
    let r = self.bitPattern.addingReportingOverflow(other.bitPattern)
    return (Self(bitPattern: r.partialValue), r.overflow)
  }

  /// Fixed-point subtraction reporting overflow.
  ///
  /// If no overflow occurs, `partialValue` is `self - other` and `overflow`
  /// is false. If `self - other` would overflow, `partialValue` holds the
  /// wrapped result, and `overflow` is true.
// BEGIN CHANGE
   @inline(always)
// END CHANGE
  public func subtractingReportingOverflow(_ other: Self) -> (
    partialValue: Self,
    overflow: Bool
  ) {
    let r = self.bitPattern.subtractingReportingOverflow(other.bitPattern)
    return (Self(bitPattern: r.partialValue), r.overflow)
  }

  /*
  @_transparent
  public func multipliedReportingOverflow(
    by other: Self, rounding rule: RoundingRule = .toNearestOrEven
  ) -> (
    partialValue: Self,
    overflow: Bool
  ) {
    let (h,t) = self.bitPattern.multipliedFullWidth(by: other.bitPattern)

  }
  */
}

// ===--- Rounding.swift ---------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

extension FixedPoint {
  /// Round to an integral value, according to the sepecified `RoundingRule`.
  ///
  /// If rounding would overflow, `nil` is returned.
  ///
  /// > Note:
  ///   See also ``rounding(_:)`` and ``roundingWithSaturation(_:)``
  @inline(always)
  public func roundingIfRepresentable(
    _ rule: RoundingRule = .toNearestOrEven
  ) -> Self? {
    let bits = bitPattern
    let int = Self.integralMask
    let frac = Self.fractionMask
    let unit = Self.unit
    let half = Self.half
    let sign = bits.signbit
    switch rule {
      // These three cases never overflow:
    case .down:
      return Self(bitPattern: bits & int)
    case .towardZero:
      return Self(bitPattern: (bits &+ (frac & sign)) & int)
    case .toOdd:
      return Self(bitPattern: (bits & int) | (bits &+ frac) & unit)
      // These have to handle overflow carefully:
    case .up:
      if case let (rounded, false) = bits.addingReportingOverflow(frac) {
        return Self(bitPattern: rounded & int)
      }
    case .awayFromZero:
      if case let (rounded, false) = bits.addingReportingOverflow(frac & ~sign) {
        return Self(bitPattern: rounded & int)
      }
    case .toNearestOrDown:
      if case let (rounded, false) = bits.addingReportingOverflow(half &- 1) {
        return Self(bitPattern: rounded & int)
      }
    case .toNearestOrUp:
      if case let (rounded, false) = bits.addingReportingOverflow(half) {
        return Self(bitPattern: rounded & int)
      }
    case .toNearestOrZero:
      if case let (rounded, false) = bits.addingReportingOverflow(half &- 1 &- sign) {
        return Self(bitPattern: rounded & int)
      }
    case .toNearestOrAway:
      if case let (rounded, false) = bits.addingReportingOverflow(half &+ sign) {
        return Self(bitPattern: rounded & int)
      }
    case .toNearestOrEven:
      let p = bits >> Self.fractionBits & 1
      if case let (rounded, false) = bits.addingReportingOverflow(half &- 1 &+ p) {
        return Self(bitPattern: rounded & int)
      }
    case .stochastically:
      if case let (rounded, false) = bits.addingReportingOverflow(.random(in: 0...frac)) {
        return Self(bitPattern: rounded & int)
      }
    case .requireExact:
      if bits & frac == 0 { return Self(bitPattern: bits & int) }
    }
    return nil
  }

  /// Round to an integral value, according to the sepecified `RoundingRule`.
  ///
  /// If rounding overflows, the result saturates to the largest or smallest
  /// representable _integral value_. For example:
  /// ```
  /// let bigNumber = MyFixedPointFormat.max               // not an integer
  /// let roundedUp = bigNumber.roundedWithSaturation(.up)
  /// ```
  /// Most other operations that saturate return the largest representable
  /// value (`.max`), but that would result in a non-integral result in this
  /// case. Instead, out-of-range values like the one shown above saturate
  /// to `.max.rounded(.down)`.
  ///
  /// This violates the very reasonable expectation that `a.rounded(.up) >= a`,
  /// but this violation is not as bad as the alternative, which is that
  /// `a.rounded(.up)` isn't an integer at all.
  ///
  /// Use ``roundingIfRepresentable(_:)`` if you have to handle overflow in
  /// a different manner.
  /*@inlinable*/
// BEGIN CHANGE
  @_transparent
  public func roundingWithSaturation(_ rule: RoundingRule = Self.defaultRounding) -> Self {
// END CHANGE
    let bits = bitPattern
    let int = Self.integralMask
    let frac = Self.fractionMask
    let unit = Self.unit
    let half = Self.half
    let sign = bits.signbit
    switch rule {
    case .down:
      return Self(bitPattern: bits & int)
    case .towardZero:
      return Self(bitPattern: (bits &+ (frac & sign)) & int)
    case .toOdd:
      return Self(bitPattern: (bits & int) | (bits &+ frac) & unit)
    case .up:
      return Self(bitPattern: bits.addingWithSaturation(frac) & int)
    case .awayFromZero:
      return Self(bitPattern: bits.addingWithSaturation(frac & ~sign) & int)
    case .toNearestOrDown:
      return Self(bitPattern: bits.addingWithSaturation(half &- 1) & int)
    case .toNearestOrUp:
      return Self(bitPattern: bits.addingWithSaturation(half) & int)
    case .toNearestOrZero:
      return Self(bitPattern: bits.addingWithSaturation(half &- 1 &- sign) & int)
    case .toNearestOrAway:
      return Self(bitPattern: bits.addingWithSaturation(half &+ sign) & int)
    case .toNearestOrEven:
      let p = bits >> Self.fractionBits & 1
      return Self(bitPattern: bits.addingWithSaturation(half &- 1 &+ p) & int)
    case .stochastically:
      return Self(bitPattern: bits.addingWithSaturation(.random(in: 0...frac)) & int)
    case .requireExact:
      precondition(bits & frac == 0, "fractional part must be zero")
      return Self(bitPattern: bits & int)
    }
  }
}

// ===--- SaturatingArithmetic.swift ---------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

extension FixedPoint {
  /// Saturating fixed-point subtraction
  ///
  /// `self - other` clamped to the representable range of the type. If the
  /// "normal subtraction" `self - other` does not trap, that result is
  /// returned. Otherwise, `subtractingWithSaturation` produces either `.min`
  /// (if the true result would be less than `.min`) or `.max` (if the true
  /// result would be greater than `.max`).
// BEGIN CHANGE
  /*@_transparent*/
  @inline(always)
  public func subtractingWithSaturation(_ other: Self) -> Self {
// END CHANGE
    Self(bitPattern: self.bitPattern.subtractingWithSaturation(other.bitPattern))
  }

  /// Saturating fixed-point multiplication
  ///
  /// `self * other` clamped to the representable range of the type. If the
  /// "normal subtraction" `self * other` does not trap, that result is
  /// returned. Otherwise, `multipliedWithSaturation` produces either `.min`
  /// (if the true result would be less than `.min`) or `.max` (if the true
  /// result would be greater than `.max`).
  @_transparent
  public func multipliedWithSaturation(
    by other: Self,
    rounding rule: RoundingRule = Self.defaultRounding
  ) -> Self {
    let (result, overflow) = self.multipliedReportingOverflow(by: other, rounding: rule)
    if !overflow { return result }
    return Self(
      bitPattern: .max &- (self.bitPattern ^ other.bitPattern).signbit
    )
  }

  /// Saturating fixed-point division
  ///
  /// `self / other` clamped to the representable range of the type. If the
  /// "normal subtraction" `self / other` does not trap, that result is
  /// returned. Otherwise, `dividedWithSaturation` produces is `.max` (if
  /// the true result would be greater than `.max`) and `.min` otherwise.
  ///
  /// > Note:
  ///   This operation does not support the rule `.requireExact` because
  ///   I haven't figured out what I want its semantics to be yet. Please
  ///   open a github issue if you have a good argument for some desired
  ///   behavior.
  @_transparent
  public func dividedWithSaturation(
    by other: Self,
    rounding rule: RoundingRule = Self.defaultRounding
  ) -> Self {
    precondition(rule != .requireExact)
    if let result = self.dividedIfRepresentable(by: other, rounding: rule) {
      return result
    }
    return (self.bitPattern ^ other.bitPattern) >= 0 ? .max : .min
  }
}

// ===--- String.swift -----------------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// BEGIN CHANGE
// import IntegerUtilities
// END CHANGE

extension FixedPoint {
  // TODO: add rounding control
  public init?(_ description: String) {
    // TODO: bypass double to avoid double-roundings
    guard let d = Double(description) else { return nil }
    self.init(ifRepresentable: d, rounding: .toNearestOrEven)
  }

  public var description: String {
    var result = ""
    if self < 0 { result = "-" }
    // isolate integral part and format as string using the existing integer
    // support
    result += String(bitPattern.magnitude >> Self.fractionBits)
    result += "."
    // isolate and left-align fractional part
    var fraction = bitPattern.magnitude << Self.integralBits
    // We need at most one decimal digit for each fractional bit
    for _ in 0 ..< Self.fractionBits {
      // Peel off one digit via multiply-high
      let (digit, residual) = fraction.multipliedFullWidth(by: 10)
      result += "\(digit)"
      if residual == 0 { break }
      fraction = residual
    }
    return result
  }
}

/* TODO: add rounding support, polish, etc
extension String {
  @inline(never) // specialize
  public init<Fixed: FixedPoint>(
    _ fixed: Fixed,
    radix: Int = 10,
    fractionalDigits: Int? = nil,
    rounding rule: RoundingRule = .toNearestOrEven,
    alwaysPrintSign: Bool = false
  ) {
    if fixed.bitPattern < 0 { self = "-" }
    else if alwaysPrintSign { self = "+" }
    else { self = "" }
    // print integer part
    let magnitude = fixed.bitPattern.magnitude
    self += String(magnitude &>> Fixed.fractionBits)
    self += "."
    // isolate fraction
    var fraction = magnitude &<< Fixed.integralBits
    var unit = Fixed.IntegerType.Magnitude(1) &<< Fixed.integralBits
    var digits = fractionalDigits ?? Fixed.fractionBits
    let r = Fixed.IntegerType.Magnitude(radix)
    while digits > 0 {
      let (dig, tail) = bits.multipliedFullWidth(by: r)
      self += "\(dig)"
      let (hi, low) = unit.multipliedFullWidth(by: r)
      if tail == 0 /*shortest WIP: hi != 0 ||  tail < low */ { break }
      bits = tail
      unit = low
      digits -= 1
    }
  }
}
*/

// ===--- DividingFull.swift -----------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

extension FixedWidthInteger {
  @_transparent
  var nextUp: Self? {
    guard case let (result, false) = addingReportingOverflow(1) else {
      return nil
    }
    return result
  }

  /// The quotient produced dividing the specified `dividend` by this value,
  /// rounding according to the specified `rule`, if it is representable.
  ///
  /// If the result is not representable, because one of the following criteria
  /// hold:
  /// - the divisor is zero
  /// - the quotient would overflow
  /// - the quotient is not exact and the rounding rule is `.requireExact`
  /// then the result is `nil`.
  /*@inlinable*/
  public func dividing(
    _ dividend: (high: Self, low: Magnitude),
    rounding rule: RoundingRule
  ) -> Self? {
    if Self.isSigned {
      // Convert to unsigned, and adjust rounding rule to match; we can
      // determine the sign of the quotient from signs of dividend and
      // divisor and swap up/down to achieve the correct direction.
      let unsignedDividend: (high: Magnitude, low: Magnitude)
      if dividend.high < 0 {
        let (low, carry) = (~dividend.low).addingReportingOverflow(1)
        let high = Magnitude(truncatingIfNeeded: ~dividend.high) &+ (carry ? 1 : 0)
        unsignedDividend = (high, low)
      } else {
        unsignedDividend = (Magnitude(truncatingIfNeeded: dividend.high), dividend.low)
      }
      let resultIsNegative = dividend.high ^ self < 0
      let unsignedRule = resultIsNegative ? rule.negated : rule
      // Do the division in unsigned; if it overflows, then signed division
      // would too.
      guard let quotient = magnitude.dividing(unsignedDividend, rounding: unsignedRule) else {
        return nil
      }
      return Self(magnitude: quotient, negated: resultIsNegative)
    }
  let addend: Magnitude
  switch rule {
  // It's generally somewhat neater to handle rounding by adding a term
  // before doing the division; the following rounding modes can be
  // handled that way:
  case .down, .towardZero:
    addend = 0

  case .up, .awayFromZero:
    addend = magnitude &- 1

  case .toNearestOrDown, .toNearestOrZero:
    addend = (magnitude &- 1) &>> 1

  case .toNearestOrUp, .toNearestOrAway:
    addend = magnitude &>> 1

  case .stochastically:
    addend = .random(in: 0 ..< magnitude)

  // These modes cannot easily be handled by just adjusting the dividend,
  // so we implement them completely here instead of using the shared
  // body that follows the switch.
  case .toOdd:
    guard dividend.high < self else { return nil }
    let (q, r) = dividingFullWidth(dividend)
    return q | (r == 0 ? 0 : 1)

  case .toNearestOrEven:
    guard dividend.high < self else { return nil }
    let (q, r) = dividingFullWidth(dividend)
    let half = (magnitude - (q.magnitude & 1)) &>> 1
    return r > half ? q.nextUp : q

  case .requireExact:
    guard dividend.high < self else { return nil }
    let (q, r) = dividingFullWidth(dividend)
    return r == 0 ? q : nil
  }

  let adjusted: (high: Self, low: Magnitude)
  var carry: Bool = false
  (adjusted.low, carry) = dividend.low.addingReportingOverflow(addend)
  (adjusted.high, carry) = dividend.high.addingReportingOverflow(carry ? 1 : 0)
  guard !carry, adjusted.high < self else { return nil }
  return dividingFullWidth(adjusted).quotient
  }

  public init?<Other: UnsignedInteger>(
    magnitude other: Other,
    negated: Bool
  ) {
    if negated {
      guard other <= Self.min.magnitude else { return nil }
      self = 0 &- Self(truncatingIfNeeded: other)
    } else {
      guard other <= Self.max else { return nil }
      self = Self(truncatingIfNeeded: other)
    }
  }

  @_transparent
  public func multiplied<Other: FixedWidthInteger>(
    by numerator: Other,
    dividedBy denominator: Other,
    rounding rule: RoundingRule = .down
  ) -> Self? {
    let resultIsNegative = (self < 0) != (numerator ^ denominator < 0)
    let magnitudeRule = resultIsNegative ? rule.negated : rule

    func mulDivMagnitudes<Compute: FixedWidthInteger & UnsignedInteger>(
      _ x: Compute, _ a: Compute, _ b: Compute
    ) -> Self? {
      let p = x.multipliedFullWidth(by: a)
      guard let q = b.dividing(p, rounding: magnitudeRule) else { return nil }
      return Self(magnitude: q, negated: resultIsNegative)
    }

    if Magnitude.bitWidth > Other.Magnitude.bitWidth {
      return mulDivMagnitudes(
        magnitude,
        Magnitude(truncatingIfNeeded: numerator.magnitude),
        Magnitude(truncatingIfNeeded: denominator.magnitude)
      )
    }
  return mulDivMagnitudes(
    Other.Magnitude(truncatingIfNeeded: magnitude),
    numerator.magnitude,
    denominator.magnitude
  )
  }
}
// ===--- RoundingRule.swift -----------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2021-2024 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// TODO: it's unfortunate that we can't specify a custom random source
// for the stochastic rounding rule, but I don't see a nice way to have
// that share the API with the other rounding rules, because we'd then
// have to take either the rule in-out or have an additional RNG/state
// parameter. The same problem applies to rounding with dithering and
// any other stateful rounding method. We should consider adding a
// stateful rounding API down the road to support those use cases.

/// A rule that defines how to select one of the two representable results
/// closest to a given value.
///
/// [Wikipedia](https://en.wikipedia.org/wiki/Rounding#Rounding_to_integer)
/// provides a good overview of different rounding rules.
///
/// Examples using rounding to integer to illustrate the various options:
/// ```
///                          Directed rounding rules
///
///  value |     down     |      up      |  towardZero  | awayFromZero |
/// =======+==============+==============+==============+==============+
///  -1.5  |      -2      |      -1      |      -1      |      -2      |
/// -------+--------------+--------------+--------------+--------------+
///  -0.5  |      -1      |       0      |       0      |      -1      |
/// -------+--------------+--------------+--------------+--------------+
///   0.5  |       0      |       1      |       0      |       1      |
/// -------+--------------+--------------+--------------+--------------+
///   0.7  |       0      |       1      |       0      |       1      |
/// -------+--------------+--------------+--------------+--------------+
///   1.2  |       1      |       2      |       1      |       2      |
/// -------+--------------+--------------+--------------+--------------+
///   2.0  |       2      |       2      |       2      |       2      |
/// -------+--------------+--------------+--------------+--------------+
///
///                      toNearestOr... rounding rules
///
///  value |  orDown  |   orUp   |  orZero  |  orAway  |  orEven  |
/// =======+==========+==========+==========+==========+==========+
///  -1.5  |    -2    |    -1    |    -1    |    -2    |    -2    |
/// -------+----------+----------+----------+----------+----------+
///  -0.5  |    -1    |     0    |     0    |    -1    |     0    |
/// -------+----------+----------+----------+----------+----------+
///   0.5  |     0    |     1    |     0    |     1    |     0    |
/// -------+----------+----------+----------+----------+----------+
///   0.7  |     1    |     1    |     1    |     1    |     1    |
/// -------+----------+----------+----------+----------+----------+
///   1.2  |     1    |     1    |     1    |     1    |     1    |
/// -------+----------+----------+----------+----------+----------+
///   2.0  |     2    |     2    |     2    |     2    |     2    |
/// -------+----------+----------+----------+----------+----------+
///
///                      Specialized rounding rules
///
///  value |    toOdd     |    stochastically     |  requireExact  |
/// =======+==============+=======================+================+
///  -1.5  |      -1      |    50% -2, 50% -1     |      trap      |
/// -------+--------------+-----------------------+----------------+
///  -0.5  |      -1      |    50% -1, 50% 0      |      trap      |
/// -------+--------------+-----------------------+----------------+
///   0.5  |       1      |     50% 0, 50% 1      |      trap      |
/// -------+--------------+-----------------------+----------------+
///   0.7  |       1      |     30% 0, 70% 1      |      trap      |
/// -------+--------------+-----------------------+----------------+
///   1.2  |       1      |     80% 1, 20% 2      |      trap      |
/// -------+--------------+-----------------------+----------------+
///   2.0  |       2      |          2            |        2       |
/// -------+--------------+-----------------------+----------------+
/// ```
// BEGIN CHANGE
public enum RoundingRule {
// END CHANGE
  /// Produces the closest representable value that is less than or equal
  /// to the value being rounded.
  ///
  /// This is the default rounding mode for integer shifts, including the
  /// shift operators defined in the standard library.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .down)` is `-2`, because –2 is the
  /// largest integer less than –4/3 = –1.3̅
  /// - `5.shifted(rightBy: 1, rounding: .down)` is `2`, because 2 is the
  /// largest integer less than 5/2 = 2.5.
  case down

  /// Produces the closest representable value that is greater than or equal
  /// to the value being rounded.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .up)` is `-1`, because –1 is the
  /// smallest integer greater than –4/3 = –1.3̅
  /// - `5.shifted(rightBy: 1, rounding: .up)` is `3`, because 3 is the
  /// smallest integer greater than 5/2 = 2.5.
  case up

  /// Produces the closest representable value whose magnitude is less than
  /// or equal to that of the value being rounded.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .towardZero)` is `-1`, because –1
  /// is the closest integer to –4/3 = –1.3̅ with smaller magnitude.
  /// - `5.shifted(rightBy: 1, rounding: .towardZero)` is `2`, because 2
  /// is the closest integer to 5/2 = 2.5 with smaller magnitude.
  case towardZero

  /// Produces the closest representable value whose magnitude is greater
  /// than or equal to that of the value being rounded.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .awayFromZero)` is `-2`, because –2
  /// is the closest integer to –4/3 = –1.3̅ with greater magnitude.
  /// - `5.shifted(rightBy: 1, rounding: .awayFromZero)` is `3`, because 3
  /// is the closest integer to 5/2 = 2.5 with greater magnitude.
  case awayFromZero

  /// If the value being rounded is representable, that value is returned.
  /// Otherwise, whichever of the two closest representable values has its
  /// least significant bit set is returned.
  ///
  /// This is also called _sticky rounding_, and it is useful as an
  /// implementation detail because it has the property that if we do
  /// rounding in two steps, first to intermediate precision p₁ with .toOdd,
  /// then to the final precision p₂ with any other rounding mode, the result
  /// we get is the same as if we rounded directly to p₂ in the desired mode
  /// so long as p₂ + 1 < p₁. Other rounding modes do not have this property,
  /// and admit _double roundings_ when interoperating with some modes.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .toOdd)` is `-1`, because –4/3 = –1.3̅
  /// is not an exact integer, and –1 is the closest odd integer.
  /// - `4.shifted(rightBy: 1, rounding: .toOdd)` is `2`,
  /// even though 2 is even, because 4/2 is exactly 2 and no rounding occurs.
  case toOdd

  /// Produces the representable value that is closest to the value being
  /// rounded. If two values are equally close, the one that is less than
  /// the value being rounded is chosen.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .toNearestOrDown)`
  /// is `-1`, because –4/3 = –1.3̅ is closer to –1 than it is to –2.
  ///
  /// - `5.shifted(rightBy: 1, rounding: .toNearestOrDown)` is `2`,
  /// because 5/2 = 2.5 is equally close to 2 and 3, and 2 is less.
  case toNearestOrDown

  /// Produces the representable value that is closest to the value being
  /// rounded. If two values are equally close, the one that is greater than
  /// the value being rounded is chosen.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .toNearestOrUp)`
  /// is `-1`, because –4/3 = –1.3̅ is closer to –1 than it is to –2.
  ///
  /// - `5.shifted(rightBy: 1, rounding: .toNearestOrUp)` is `3`,
  /// because 5/2 = 2.5 is equally close to 2 and 3, and 3 is greater.
  case toNearestOrUp

  /// Produces the representable value that is closest to the value being
  /// rounded. If two values are equally close, the one that has smaller
  /// magnitude is returned.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .toNearestOrZero)`
  /// is `-1`, because –4/3 = –1.3̅ is closer to –1 than it is to –2.
  ///
  /// - `5.shifted(rightBy: 1, rounding: .toNearestOrZero)` is `3`,
  /// because 5/2 = 2.5 is equally close to 2 and 3, and 2 is closer to zero.
  case toNearestOrZero

  /// Produces the representable value that is closest to the value being
  /// rounded. If two values are equally close, the one that has greater
  /// magnitude is returned.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .toNearestOrAway)`
  /// is `-1`, because –4/3 = –1.3̅ is closer to –1 than it is to –2.
  ///
  /// - `5.shifted(rightBy: 1, rounding: .toNearestOrAway)` is `3`,
  /// because 5/2 = 2.5 is equally close to 2 and 3, and 3 is further away
  /// from zero.
  case toNearestOrAway

  /// Produces the representable value that is closest to the value being
  /// rounded. If two values are equally close, the one whose least
  /// significant bit is not set is returned.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .toNearestOrEven)`
  /// is `-1`, because –4/3 = –1.3̅ is closer to –1 than it is to –2.
  ///
  /// - `5.shifted(rightBy: 1, rounding: .toNearestOrEven)` is `2`,
  /// because 5/2 = 2.5 is equally close to 2 and 3, and 2 is even.
  case toNearestOrEven

  /// Adds a uniform random value from [0, d) to the value being rounded,
  /// where d is the distance between the two closest representable values,
  /// then rounds the sum downwards.
  ///
  /// Unlike all the other rounding modes, this mode is _not deterministic_;
  /// repeated calls to rounding operations with this mode will generally
  /// produce different results. There is a tradeoff implicit in using this
  /// mode: you can sacrifice _reproducible_ results to get _more accurate_
  /// results in aggregate. For a contrived but illustrative example, consider
  /// the following:
  /// ```
  /// let data = Array(repeating: 1, count: 100)
  /// let result = data.reduce(0) {
  ///   $0 + $1.divided(by: 3, rounding: rule)
  /// }
  /// ```
  /// because 1/3 is always the same value between 0 and 1, any
  /// deterministic rounding rule must produce either 0 or 100 for
  /// this computation. But rounding `stochastically` will
  /// produce a value close to 33. The _error_ of the computation
  /// is smaller, but the result will now change between runs of the
  /// program.
  ///
  /// For this simple case a better solution would be to add the
  /// values first, and then divide. This gives a result that is both
  /// reproducible _and_ accurate:
  /// ```
  /// let result = data.reduce(0, +)/3
  /// ```
  /// but this isn't always possible in more sophisticated scenarios,
  /// and in those cases this rounding rule may be useful.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .stochastically)`
  /// will be –1 with probability 2/3 and –2 with probability 1/3.
  /// - `5.shifted(rightBy: 1, rounding: .stochastically)`
  /// will be 2 with probability 1/2 and 3 with probability 1/2.
  case stochastically

  /// If the value being rounded is representable, that value is returned.
  /// Otherwise, a precondition failure occurs.
  ///
  /// Examples:
  /// - `(-4).divided(by: 3, rounding: .requireExact)` will trap,
  /// because –4/3 = –1.3̅ is not an integer.
  case requireExact
}

extension RoundingRule {
  /// "Negates" this rounding rule; if `x` rounded according to `rule`
  /// produces a result `y`, then `-x` rounded according to `rule.negated`
  /// produces the result `-y`.
  @_transparent
  public var negated: RoundingRule {
    switch self {
    case .down:            return .up
    case .up:              return .down
    case .towardZero:      return .towardZero
    case .awayFromZero:    return .awayFromZero
    case .toNearestOrDown: return .toNearestOrUp
    case .toNearestOrUp:   return .toNearestOrDown
    case .toNearestOrZero: return .toNearestOrZero
    case .toNearestOrAway: return .toNearestOrAway
    case .toNearestOrEven: return .toNearestOrEven
    case .toOdd:           return .toOdd
    case .stochastically:  return .stochastically
    case .requireExact:    return .requireExact
    }
  }
}

extension FloatingPoint {
  /// `self` rounded to integer according to `rule`.
  ///
  /// This mirrors the standard library `rounded` API, providing access to
  /// the expanded set of rounding rules defined in IntegerUtilities. It is
  /// not just a shadow because that would lead to ambiguity errors in
  /// existing code that uses the shortened `rounded(.down)` form.
  @inline(always)
  public func rounding(_ rule: RoundingRule) -> Self {
    switch rule {
    case .down:
      return rounded(.down)
    case .up:
      return rounded(.up)
    case .towardZero:
      return rounded(.towardZero)
    case .awayFromZero:
      return rounded(.awayFromZero)
    case .toNearestOrDown:
      // FP doesn't have toNearestOrDown, so round toNearestOrEven and fixup
      // any exact-halfway cases.
      let nearest = rounded(.toNearestOrEven)
      return nearest - self == 1 / 2 ? rounded(.down) : nearest
    case .toNearestOrUp:
      // FP doesn't have toNearestOrUp, so round toNearestOrEven and fixup
      // any exact-halfway cases.
      let nearest = rounded(.toNearestOrEven)
      return self - nearest == 1 / 2 ? rounded(.up) : nearest
    case .toNearestOrZero:
      // FP doesn't have toNearestOrZero, so round toNearestOrEven and fixup
      // any exact-halfway cases.
      let nearest = rounded(.toNearestOrEven)
      return (self - nearest).magnitude == 1 / 2 ? rounded(.towardZero) : nearest
    case .toNearestOrAway:
      return self.rounded(.toNearestOrAwayFromZero)
    case .toNearestOrEven:
      return self.rounded(.toNearestOrEven)
    case .toOdd:
      let trunc = rounded(.towardZero)
      if trunc == self { return trunc }
      let one = Self(signOf: self, magnitudeOf: 1)
      // We have eliminated all large values at this point; add ±0.5, and see
      // which way that rounds, then select the other value.
      let even = (trunc + one / 2).rounded(.toNearestOrEven)
      return trunc == even ? trunc + one : trunc
    case .stochastically:
      let trunc = rounded(.towardZero)
      if trunc == self { return trunc }
      // We have eliminated all large values at this point; add dither in
      // ±[0,1) and then truncate.
      let bits = Swift.min(-Self.ulpOfOne.exponent, 32)
      let random = Self(UInt32.random(in: 0 ... (1 << bits &- 1)))
      let dither = Self(sign: sign, exponent: -bits, significand: random)
      return (self + dither).rounded(.towardZero)
    case .requireExact:
      let trunc = rounded(.towardZero)
      precondition(isInfinite || trunc == self, "\(self) is not an exact integer.")
      return self
    }
  }
}

// ===--- SaturatingArithmetic.swift ---------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2023 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

extension FixedWidthInteger {
  /// `~0` (all-ones) if this value is negative, otherwise `0`.
  ///
  /// Note that if `Self` is unsigned, this always returns `0`,
  /// but it is useful for writing algorithms that are generic over
  /// signed and unsigned integers.

// BEGIN CHANGE
public var signbit: Self {
// END CHANGE
    self < .zero ? ~.zero : .zero
  }

  /// Saturating integer addition
  ///
  /// `self + other` clamped to the representable range of the type. e.g.:
  /// ```
  /// let a: Int8 = 84
  /// let b: Int8 = 100
  /// // 84 + 100 = 184 is not representable as
  /// // Int8, so `c` is clamped to Int8.max (127).
  /// let c = a.addingWithSaturation(b)
  /// ```
  ///
  /// Anytime the "normal addition" `self + other` does not trap,
  /// `addingWithSaturation` produces the same result.
  /*@inlinable*/
  public func addingWithSaturation(_ other: Self) -> Self {
    let (wrapped, overflow) = addingReportingOverflow(other)
    return overflow ? Self.max &- signbit : wrapped
  }

  /// Saturating integer subtraction
  ///
  /// `self - other` clamped to the representable range of the type. e.g.:
  /// ```
  /// let a: UInt = 37
  /// let b: UInt = 42
  /// // 37 - 42 = -5, which is not representable as
  /// // UInt, so `c` is clamped to UInt.min (zero).
  /// let c = a.subtractingWithSaturation(b)
  /// ```
  ///
  /// Note that `a.addingWithSaturation(-b)` is not always equivalent to
  /// `a.subtractingWithSaturation(b)`, because `-b` is not representable
  /// if `b` is the minimum value of a signed type.
  ///
  /// Anytime the "normal subtraction" `self - other` does not trap,
  /// `subtractingWithSaturation` produces the same result.
  /*@inlinable*/
  public func subtractingWithSaturation(_ other: Self) -> Self {
    let (wrapped, overflow) = subtractingReportingOverflow(other)
    if !overflow { return wrapped }
    return Self.isSigned ? Self.max &- signbit : 0
  }
}

// ===--- ShiftWithRounding.swift ------------------------------*- swift -*-===//
//
// This source file is part of the Swift Numerics open source project
//
// Copyright (c) 2021 Apple Inc. and the Swift Numerics project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

extension BinaryInteger {
  /// `self` divided by 2^(`count`), rounding the result according to `rule`.
  ///
  /// The default rounding rule is `.down`, which matches the behavior of
  /// the `>>` operator from the standard library.
  ///
  /// Some examples of different rounding rules:
  ///
  ///     // 3/2 is 1.5, which rounds (down by default) to 1.
  ///     3.shifted(rightBy: 1)
  ///
  ///     // 1.5 rounds up to 2.
  ///     3.shifted(rightBy: 1, rounding: .up)
  ///
  ///     // The two closest values are 1 and 2, 1 is returned because it
  ///     // is odd.
  ///     3.shifted(rightBy: 1, rounding: .toOdd)
  ///
  ///     // 7/4 = 1.75, so the result is 1 with probability 1/4, or 2
  ///     // with probability 3/4.
  ///     7.shifted(rightBy: 2, rounding: .stochastically)
  ///
  ///     // 4/4 is exactly 1, so this does not trap.
  ///     4.shifted(rightBy: 2, rounding: .requireExact)
  ///
  ///     // 5/2 is 2.5, which is not an integer, so this traps.
  ///     5.shifted(rightBy: 1, rounding: .requireExact)
  ///
  /// When `Self(1) << count` is positive, the following are equivalent:
  ///
  ///     a.shifted(rightBy: count, rounding: rule)
  ///     a.divided(by: 1 << count, rounding: rule)
  /*@inlinable*/
  public func shifted(
    rightBy count: Int,
    rounding rule: RoundingRule = .down
  ) -> Self {
    // Easiest case: count is zero or negative, so shift is always exact;
    // delegate to the normal >> operator.
    if count <= 0 { return self >> count }
    if count >= bitWidth {
      // Note: what follows would cause an infinite loop if bitWidth <= 1.
      // This will essentially never happen, but in the highly unlikely event
      // that we encounter such a case, we promote to Int8, do the shift, and
      // then convert back to the appropriate result type.
      if bitWidth <= 1 {
        return Self(Int8(self).shifted(rightBy: count, rounding: rule))
      }
      // That pathological case taken care of, we can now handle over-wide
      // shifts by first shifting all but bitWidth - 1 bits with sticky
      // rounding, and then shifting the remaining bitWidth - 1 bits with
      // the desired rounding mode.
      let count = count - (bitWidth - 1)
      let floor = self >> count
      let lost = self - (floor << count)
      let sticky = floor | (lost == 0 ? 0 : 1)
      return sticky.shifted(rightBy: bitWidth - 1, rounding: rule)
    }
    // Now we are in the happy case: 0 < count < bitWidth, which makes all
    // the math to handle rounding simpler.
    //
    // TODO: If we were really, really careful about overflow, some of these
    // could be made simpler. E.g. mathematically round up is implemented here
    // via:
    //
    //   floor = self >> count
    //   mask = 1 << count - 1
    //   lost = self & mask
    //   return floor + (lost == 0 ? 0 : 1)
    //
    // _if_ we didn't have to worry about intermediate overflow (either because
    // self is bounded away from .max or because we don't have a fixed-width
    // type), then we could use the following instead:
    //
    //   mask = 1 << count - 1
    //   return (self + mask) >> count
    //
    // However, self + mask can overflow, e.g. if we're shifting .max by 1:
    //
    //   mask = 1 << 1 - 1 = 1
    //   self + mask = .max + 1 // uh-oh
    //
    // This cannot occur for arbitrary-precision numbers, so we could use
    // the simpler expressions for those (but those are precisely the cases
    // where performance of rounding does not matter much, because shifts
    // get swamped by even basic arithmetic). More interesting, we could
    // promote fixed-width numbers to a wider type, preventing this
    // intermediate overflow and allowing us to use the simpler expressions
    // much of the time. We could also explicitly _detect_ the overflow if
    // it happens and patch up the result, though this is a little bit tricky
    // because addingReportingOverflow and friends do not exist on
    // BinaryInteger. Hence, this is a TODO for the future.
    let mask = Magnitude(1) << count - 1
    let lost = Magnitude(truncatingIfNeeded: self) & mask
    let floor = self >> count
    let ceiling = floor + (lost == 0 ? 0 : 1)
    let half: Magnitude = (1 as Magnitude) << (count &- 1)
    switch rule {
    case .down:
      return floor
    case .up:
      return ceiling
    case .towardZero:
      return self > 0 ? floor : ceiling
    case .awayFromZero:
      return self < 0 ? floor : ceiling
    case .toNearestOrDown:
      return floor + Self((lost + (half - 1)) >> count)
    case .toNearestOrUp:
      return floor + Self((lost + half) >> count)
    case .toNearestOrZero:
      let round = half - (self < 0 ? 0 : 1)
      return floor + Self((round + lost) >> count)
    case .toNearestOrAway:
      let round = half - (self > 0 ? 0 : 1)
      return floor + Self((round + lost) >> count)
    case .toNearestOrEven:
      let round = mask >> 1 + Magnitude(floor & 1)
      return floor + Self((round + lost) >> count)
    case .toOdd:
      return floor | (lost == 0 ? 0 : 1)
    case .stochastically:
      // In theory, u01 should be Self.random(in: 0 ..< onesBit), but the
      // random(in:) method does not exist on BinaryInteger. This is
      // (arguably) good, though, because there's actually no reason to
      // generate large amounts of randomness just to implement stochastic
      // rounding; 32b suffices for almost all purposes, and 64b is more
      // than enough.
      var g = SystemRandomNumberGenerator()
      let u01 = g.next()
      if count < 64 {
        // count is small, so mask and lost are representable as both
        // UInt64 and Self, regardless of what type Self actually is.
        return floor + Self(((u01 & UInt64(mask)) + UInt64(lost)) >> count)
      }
    // count is large, so lost may not be representable as UInt64; pre-
    // shift by count-64 to isolate the high 64b of the fraction, then
    // add u01 and carry-out to round.
    let highWord = UInt64(truncatingIfNeeded: lost >> (Int(count) - 64))
    let (_, carry) = highWord.addingReportingOverflow(u01)
    return floor + (carry ? 1 : 0)
    case .requireExact:
      precondition(lost == 0, "shift was not exact.")
      return floor
    }
  }
}
