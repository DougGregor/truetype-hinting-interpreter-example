extension SwiftTrueTypeInterpreter {
  /// Current state of the TrueType interpreter's graphics engine.
  public struct GraphicsState {
    /// Controls whether MIRP/MIAP instructions ignore sign of CVT entries
    public var autoFlip: Bool = true

    /// Axis that is always marked as touched by SVTCA
    public var alwaysTouchAxis: Axis?

    /// Base value for calculating DELTA instruction pixel size ranges
    public var deltaBase: Int16 = 9

    /// Determines step size and range for DELTA instruction movements
    public var deltaShift: Int16 = 3

    /// Number of times certain instructions repeat
    public var loop: Int32 = 1

    /// Smallest possible value to which distances are rounded
    public var minimumDistance: F26Dot6 = 1  // default is "1 pixel"

    /// Determines how values are rounded
    public var roundState: RoundState = .rtg

    /// First reference point
    public var rp0: Int = 0

    /// Second reference point
    public var rp1: Int = 0

    /// Third reference point
    public var rp2: Int = 0

    /// Controls TrueType hinting program behavior
    public var instructControl: InstructControl = .init()

    /// Controls scan conversion and dropout behavior
    public var scanControl: ScanControl = .init()

    /// First zone pointer (glyph or twilight zone)
    public var zp0: Zone.ZoneType = .glyph

    /// Second zone pointer (glyph or twilight zone)
    public var zp1: Zone.ZoneType = .glyph

    /// Third zone pointer (glyph or twilight zone)
    public var zp2: Zone.ZoneType = .glyph

    /// Resets graphics state to initial values using provided parameters.
    ///
    /// - Parameter parameters: Configuration parameters to apply
    mutating func reset(_ parameters: Parameters) {
      rp0 = 0
      rp1 = 0
      rp2 = 0
      zp0 = .glyph
      zp1 = .glyph
      zp2 = .glyph
      freedomVector = .x_axis
      projectionVector = .x_axis
      alwaysTouchAxis = .x
      loop = 1

      memoizedScale = nil

      autoFlip = parameters.autoFlip
      deltaBase = parameters.deltaBase
      deltaShift = parameters.deltaShift
      instructControl = parameters.instructControl
      minimumDistance = parameters.minimumDistance
      roundState = parameters.roundState
      scanControl = parameters.scanControl
    }

    private var cachedProjDotFree: F2Dot14? = 1

    // When the dot product between freedom and projection vectors is nearly orthogonal, in other words
    // when the dot product is nearly zero, our geometry operations won't converge. No matter how far you
    // move a point along a freedom vector aligned with the X axis, you'll never end up changing its distance
    // along a projection vector aligned with the Y axis. Worse, dividing by the zero dot product will trap.
    // The old interpreter detected this situation and defended itself by ensuring that the freedom
    // and projection vectors always had a dot product of at least 1/16th. If the dot product was smaller,
    // the interpreter just gave up and acted as if their dot product was 1.0.
    fileprivate let minimumPdotF: F2Dot14 = 0.0625  // 1/16th
    fileprivate let safePdotF: F2Dot14 = 1

    @inline(always) @_transparent
    private func calculatePdotF() -> F2Dot14 {
      switch (projectionVector, freedomVector) {
      case (.x_axis, .x_axis), (.y_axis, .y_axis):
        return 1
      case (.y_axis, .x_axis), (.x_axis, .y_axis):
        return safePdotF
      default:
        let PdotF = projectionVector.dot(freedomVector)
        if PdotF > F2Dot14.min, abs(PdotF) < minimumPdotF {
          return PdotF < 0 ? -safePdotF : safePdotF
        }
        return PdotF
      }
    }

    /// Computes dot product of projection and freedom vectors.
    ///
    /// - Returns: Dot product value
    @inline(always) @_transparent
    mutating func projDotFree() -> F2Dot14 {
      if let result = cachedProjDotFree { return result }
      let PdotF: F2Dot14 = calculatePdotF()
      cachedProjDotFree = PdotF
      return PdotF
    }

    /// Vector defining the direction in which points can be moved.
    public var freedomVector: FixedVector<F2Dot14> = .x_axis {
      didSet {
        cachedProjDotFree = nil
        // modifying the freedom vector also resets alwaysTouchAxis,
        // which SVTCA then re-set as needed.
        alwaysTouchAxis = nil
      }
    }

    /// Sets the freedom vector to the projection vector
    ///
    /// Bincompat: this implements SFVTPV in a reference-compatible way. It is tempting to extend this optimization to
    /// `calculatePdotF`, but the reference rounding behaviour occasionally resulted in `projDotFree` values that were
    /// one epsilon away from 1.0; the Swift rewrite chose to maintain exact behaviour.
    @inline(always) @_transparent
    mutating func setFreedomVectorToProjectionVector() {
      freedomVector = projectionVector
      cachedProjDotFree = 1
    }

    public private(set) var _dualProjectionVector: FixedVector<F2Dot14>?
    /// Second projection vector for measuring distances from original outline
    public var dualProjectionVector: FixedVector<F2Dot14> {
      get { _dualProjectionVector ?? projectionVector }
      set { _dualProjectionVector = newValue }
    }

    /// Vector defining the direction along which distances are measured.
    public var projectionVector: FixedVector<F2Dot14> = .x_axis {
      didSet {
        projectionVectorIsNormal = false
        cachedProjDotFree = nil
        // modifying the projection vector clears the dual projection
        // vector in all cases except SDPVTL (which sets it after
        // modifying projectionVector).
        _dualProjectionVector = nil
        // modifying the projection vector also resets alwaysTouchAxis,
        // which SVTCA then re-set as needed.
        alwaysTouchAxis = nil
      }
    }

    /// Indicates whether the projection vector was set 90° ("normal") to a line
    public var projectionVectorIsNormal: Bool = false

    /// Computes a delta (measured against the projection vector) along the freedom vector.
    public mutating func vector(for distance: F26Dot6) -> FixedVector<F26Dot6> {
      let projDotFree = projDotFree()
      if projDotFree == 1 {
        return .init(scaling: distance, by: freedomVector)
      }
      return .init(
        x: distance.mulDiv(freedomVector.x, projDotFree, rounding: .towardZero),
        y: distance.mulDiv(freedomVector.y, projDotFree, rounding: .towardZero)
      )
    }

    private var memoizedScale: (FixedVector<F2Dot14>, FixedVector<F16Dot16>, F16Dot16)?
    /// Computes effective scaling factor for given stretch vector.
    ///
    /// - Parameter stretch: Stretch vector
    /// - Returns: Effective scale factor
    public mutating func effectiveScale(for stretch: FixedVector<F16Dot16>) -> F16Dot16 {
      if projectionVector.y == 0 {
        return stretch.x
      }
      if projectionVector.x == 0 {
        return stretch.y
      }

      if stretch.x == 1, stretch.y == 1 {
        return 1
      }

      if let memo = memoizedScale, memo.0 == projectionVector, memo.1 == stretch {
        return memo.2
      }

      let result: F16Dot16
      if projectionVectorIsNormal { /* thanks to the great Rob Johnson and Yingjie Ling */
        result = stretch.mixedMulRoundingToNearestOrAway(projectionVector).magnitude()
      } else {
        let mag = FixedVector(
          x: stretch.y,
          y: stretch.x  // Note the reversed axes—this vector is rotated!
        ).mixedMulRoundingToNearestOrAway(projectionVector)
        // Compat: reference interpreter promotes to double and casts back, rounding toward zero
        result = stretch.x.mulDiv(stretch.y, mag.magnitude(), rounding: .towardZero)
      }
      memoizedScale = (projectionVector, stretch, result)
      return result
    }
  }
}

extension SwiftTrueTypeInterpreter.GraphicsState {
  /// Controls scan conversion behavior.
  public struct ScanControl: RawRepresentable, Hashable {
    public var rawValue: UInt32

    public init(rawValue: UInt32) {
      self.rawValue = rawValue
    }

    /// Creates scan control with default values.
    public init() {
      self.init(rawValue: 0)
    }

    /// High 16 bits of the scan control value.
    public var highBits: UInt16 {
      get { UInt16(rawValue >> UInt16.bitWidth) }
      set {
        rawValue &= UInt32(UInt16.max)
        rawValue |= UInt32(newValue) << UInt16.bitWidth
      }
    }

    /// Low 16 bits of the scan control value.
    public var lowBits: UInt16 {
      get { UInt16(rawValue & UInt32(UInt16.max)) }
      set {
        rawValue &= ~UInt32(UInt16.max)
        rawValue |= UInt32(newValue)
      }
    }

    /// Type of scan control currently active.
    public var kind: ScanControlKind {
      get { ScanControlKind(rawValue: highBits) }
      set { highBits = newValue.rawValue }
    }
  }

  /// Specific scan control behaviors.
  public struct ScanControlKind: RawRepresentable, Hashable {
    public var rawValue: UInt16

    public init(rawValue: UInt16) {
      self.rawValue = rawValue
    }

    /// No special scan control.
    public static var noControl: Self { Self(rawValue: 0) }
    /// Stub control mode.
    public static var stubControl: Self { Self(rawValue: 1) }
    /// No dropout control mode.
    public static var noDoControl: Self { Self(rawValue: 2) }
  }

  /// Controls TrueType hinting program behavior.
  public struct InstructControl: OptionSet, Hashable {
    public var rawValue: UInt8

    public init(rawValue: UInt8) {
      self.rawValue = rawValue
    }

    /// Disable grid fitting.
    public static var noGridFit: Self { Self(rawValue: 1 << 0) }
    /// Use default TrueType hinting program control settings.
    public static var `default`: Self { Self(rawValue: 1 << 1) }
  }
}
