extension SwiftTrueTypeInterpreter.GraphicsState {
  /// Configuration for rounding operations in the graphics state.
  public struct RoundState: Equatable {
    public typealias F26Dot6 = SwiftTrueTypeInterpreter.F26Dot6
    public typealias F58Dot6 = SwiftTrueTypeInterpreter.F58Dot6
    public typealias F28Dot36 = SwiftTrueTypeInterpreter.F28Dot36
    public typealias F2Dot30 = SwiftTrueTypeInterpreter.F2Dot30

    static let oneHalf: F26Dot6 = 0.5
    static let oneQuarter: F26Dot6 = 0.25

    /// No rounding applied.
    public static var noRounding: Self {
      .init(period: .init(bitPattern: 1), phase: 0, threshold: 0)
    }

    /// Round toward zero.
    public static var towardZero: Self {
      .init(period: 1, phase: 0, threshold: 0)
    }

    /// Round away from zero.
    public static var awayFromZero: Self {
      .init(period: 1, phase: 0, threshold: F26Dot6(bitPattern: F26Dot6.fractionMask))
    }

    /// Round to nearest or away from zero
    public static var toNearestOrAway: Self {
      .init(period: 1, phase: 0, threshold: oneHalf)
    }

    /// Round toward 0, then add ±0.5
    public static var towardZeroThenHalfpoint: Self {
      .init(period: 1, phase: oneHalf, threshold: oneHalf)
    }

    /// Round to nearest 0.5 increment
    public static var toHalfpoint: Self {
      .init(period: oneHalf, phase: 0, threshold: oneQuarter)
    }

    /// Rounding off: alias for no rounding.
    public static var roff: Self { .noRounding }

    /// Round down to grid: alias for round toward zero.
    public static var rdtg: Self { .towardZero }

    /// Round up to grid: alias for round away from zero.
    public static var rutg: Self { .awayFromZero }

    /// Round to grid: alias for round to nearest or away.
    public static var rtg: Self { .toNearestOrAway }

    /// Round to half grid: alias for round toward zero then halfpoint.
    public static var rthg: Self { .towardZeroThenHalfpoint }

    /// Round to double grid: alias for round to halfpoint.
    public static var rtdg: Self { .toHalfpoint }

    /// Creates a round state from super round parameter.
    ///
    /// - Parameter param: Super round parameter byte
    public init(superRoundParameter param: UInt8) {
      let periodBits = param >> 6
      let period: F26Dot6
      switch periodBits {
      case 0, 1, 2:
        period = F26Dot6(bitPattern: 1 << (F26Dot6.fractionBits + Int(periodBits) - 1))
      default:
        period = F26Dot6(bitPattern: Self.garbagePeriod())
      }
      let (phase, threshold) = phaseAndThreshold(fromBits: param, period: period)
      self.init(period: period, phase: phase, threshold: threshold)
    }

    static let super45RoundPeriod0: F2Dot30 = 0x1.6a09e667f3bcdp-2  // sqrt(2) / 4
    static let super45RoundPeriod1: F2Dot30 = 0x1.6a09e667f3bcdp-1  // sqrt(2) / 2
    static let super45RoundPeriod2: F2Dot30 = 0x1.6a09e667f3bcdp+0  // sqrt(2)

    /// Creates a round state from super 45-degree round parameter.
    ///
    /// - Parameter param: Super 45-degree round parameter byte
    public init(super45RoundParameter param: UInt8) {
      let period: F2Dot30
      let periodOffset = 6
      switch param >> periodOffset {
      case 0: period = Self.super45RoundPeriod0
      case 1: period = Self.super45RoundPeriod1
      case 2: period = Self.super45RoundPeriod2
      default: period = F2Dot30(bitPattern: Self.garbagePeriod())
      }
      let (phase, threshold) = phaseAndThreshold(fromBits: param, period: F26Dot6(period))
      self.init(period45: period, phase: phase, threshold: threshold)
    }

    /// Rounds a value according to the configured rounding state.
    ///
    /// - Parameter value: Value to round
    /// - Returns: Rounded value
    public func round(_ value: F26Dot6) -> F26Dot6 {
      let rounded = value < 0 ? 0 &- doRoundPositive(0 &- value) : doRoundPositive(value)
      if (value < 0) == (rounded < 0) {
        // no overflow
        return rounded
      }
      if value > 0 {
        return .init(phase)
      }
      return -.init(phase)
    }

    // MARK: -
    /// Rounding method to use.
    public enum Method {
      /// Use bit masking for rounding.
      case mask
      /// Use division for rounding.
      case divide
    }

    public static func garbagePeriod<T: ExpressibleByIntegerLiteral>() -> T { 999 }

    /// Rounding method currently configured.
    public var method: Method

    /// Phase offset for rounding.
    public var phase: F26Dot6

    /// Threshold value for rounding decisions.
    public var threshold: F26Dot6

    /// Rounding period.
    public var period: F26Dot6

    /// 45-degree rounding period.
    public var period45: F28Dot36

    private init(period: F26Dot6, phase: F26Dot6, threshold: F26Dot6) {
      self.period = period
      self.period45 = 0
      self.phase = phase
      self.threshold = threshold
      self.method = .mask
    }

    private init(period45: F2Dot30, phase: F26Dot6, threshold: F26Dot6) {
      self.period = .init(period45)
      self.period45 = .init(period45)
      self.phase = phase
      self.threshold = threshold
      self.method = .divide
    }

    @inline(always) @_transparent
    private func doRoundPositive(_ value: F26Dot6) -> F26Dot6 {
      var result = value
      result &+= threshold - phase
      switch method {
      case .mask:
        result.bitPattern &= (-period).bitPattern

      case .divide:
        // Promote to F28Dot36 for the intermediate division, then back to F26Dot6.
        guard let divided = F28Dot36(result).dividedIfRepresentable(by: period45) else {
          // XXX: the reference implementation turns those to doubles for the division
          // then cast back to int, but this is UB in C++ and the results might
          // not be consistent across architectures. If the result is not
          // representable, we return -1, which the upper layer will interpret
          // as a sign shift and bail out for.
          return -1
        }

        result = reducePrecisionAndDropTopBits(divided, rounding: .down)
        result.bitPattern &= F26Dot6.integralMask
        // Promote again to F28Dot36 for multiplication, then once more back to F26Dot6.
        guard case (let multiplied, false) = F28Dot36(result).multipliedReportingOverflow(by: period45) else {
          return -1
        }
        result = reducePrecisionAndDropTopBits(multiplied, rounding: .toNearestOrAway)
      }
      result &+= phase
      return result
    }

    @inline(always) @_transparent
    private func reducePrecisionAndDropTopBits(_ value: F28Dot36, rounding rule: RoundingRule) -> F26Dot6 {
      let sixBitPrecision = F58Dot6(value, rounding: rule)
      return .init(bitPattern: .init(truncatingIfNeeded: sixBitPrecision.bitPattern))
    }
  }
}

// SROUND/S45ROUND byte encoding: bits 4-5 = phase (2-bit), bits 0-3 = threshold (4-bit)
private let kPhaseFieldShift = 4
private let kThresholdFieldMask: UInt8 = 0xf
private let kPhaseSubdivisions: Int32 = 4
private let kThresholdSubdivisions: Int32 = 8
private let kThresholdBias: Int8 = 4

@inline(always) @_transparent
private func phaseAndThreshold(
  fromBits bits: UInt8,
  period: SwiftTrueTypeInterpreter.F26Dot6
) -> (SwiftTrueTypeInterpreter.F26Dot6, SwiftTrueTypeInterpreter.F26Dot6) {
  let periodPattern = period.bitPattern
  let phaseBits = bits >> kPhaseFieldShift & 3
  let thresholdBits = bits & kThresholdFieldMask

  // divide by kPhaseSubdivisions rounding to nearest or away from 0
  let phase = (2 + periodPattern * SwiftTrueTypeInterpreter.F26Dot6.IntegerType(phaseBits)) / kPhaseSubdivisions

  let threshold =
  thresholdBits == 0
  ? periodPattern - 1
  // LOAD-BEARING RIGHT SHIFT: signed division rounds towards zero,
  // while right shifts round down. This matters for negative numbers.
  // The C++ interpreter uses a right shift.
  : (kThresholdSubdivisions / 2 + SwiftTrueTypeInterpreter.F26Dot6.IntegerType(
    Int8(thresholdBits) - kThresholdBias
  ) * periodPattern) >> 3
  return (.init(bitPattern: phase), .init(bitPattern: threshold))
}
