extension SwiftTrueTypeInterpreter {
  /// 58.6 fixed-point number, operations round to nearest or away by default.
  public struct F58Dot6: FixedPoint, BitwiseCopyable, Sendable {
    public var bitPattern: Int64
    @_transparent public static var fractionBits: Int { 6 }

    @_transparent public init(bitPattern: IntegerType) {
      self.bitPattern = bitPattern
    }

    @_transparent public static var defaultRounding: RoundingRule { .toNearestOrAway }
  }

  /// 28.36 fixed-point number, operations round to nearest or away by default.
  public struct F28Dot36: FixedPoint, BitwiseCopyable, Sendable {
    public var bitPattern: Int64
    @_transparent public static var fractionBits: Int { 36 }

    @_transparent public init(bitPattern: IntegerType) {
      self.bitPattern = bitPattern
    }

    @_transparent public static var defaultRounding: RoundingRule { .toNearestOrAway }
  }

  /// 2.30 fixed-point number, operations round to nearest or away by default.
  public struct F2Dot30: FixedPoint, BitwiseCopyable, Sendable {
    public var bitPattern: Int32
    @_transparent public static var fractionBits: Int { 30 }

    @_transparent public init(bitPattern: IntegerType) {
      self.bitPattern = bitPattern
    }

    @_transparent public static var defaultRounding: RoundingRule { .toNearestOrAway }
  }

  /// 26.6 fixed-point number, operations round to nearest or up by default.
  public struct F26Dot6: FixedPoint, BitwiseCopyable, Sendable {
    public var bitPattern: Int32
    @_transparent public static var fractionBits: Int { 6 }

    @_transparent public init(bitPattern: IntegerType) {
      self.bitPattern = bitPattern
    }

    @_transparent public static var defaultRounding: RoundingRule { .toNearestOrUp }
  }

  /// 18.14 fixed-point number, operations round to nearest or away by default.
  public struct F18Dot14: FixedPoint, BitwiseCopyable, Sendable {
    public var bitPattern: Int32
    @_transparent public static var fractionBits: Int { 14 }

    @_transparent public init(bitPattern: IntegerType) {
      self.bitPattern = bitPattern
    }

    @_transparent public static var defaultRounding: RoundingRule { .toNearestOrAway }
  }

  /// 16.16 fixed-point number, operations round to nearest or up by default.
  public struct F16Dot16: FixedPoint, BitwiseCopyable, Sendable {
    public var bitPattern: Int32
    @_transparent public static var fractionBits: Int { 16 }

    @_transparent public init(bitPattern: IntegerType) {
      self.bitPattern = bitPattern
    }

    @_transparent public static var defaultRounding: RoundingRule { .toNearestOrUp }
  }

  /// 2.14 fixed-point number, operations round to nearest or away by default.
  public struct F2Dot14: FixedPoint, BitwiseCopyable, Sendable {
    public var bitPattern: Int16
    @_transparent public static var fractionBits: Int { 14 }

    @_transparent public init(bitPattern: IntegerType) {
      self.bitPattern = bitPattern
    }

    @_transparent public static var defaultRounding: RoundingRule { .toNearestOrAway }
  }
}
