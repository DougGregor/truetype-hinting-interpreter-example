extension SwiftTrueTypeInterpreter {
  // 17/16 comes from the spec, turn it into a fixed point number transparently
  static let kDefaultControlValueCutIn: F26Dot6 = .init(bitPattern: 17 * (1 << F26Dot6.fractionBits) / 16)

  /// Control value table for TrueType hinting program variables.
  ///
  /// Provides indexed storage for control values that can be read and written
  /// by TrueType instructions, along with cut-in and single width parameters.
  struct ControlValueTable: ~Copyable {
    /// Distance threshold for control value table usage.
    var controlValueCutIn: F26Dot6

    /// Distance threshold for single width value usage.
    var singleWidthCutIn: F26Dot6 = 0

    /// Single width value used for regularizing distances.
    var singleWidthValue: ControlValue = .init(fUnits: 0)

    private var rawValues: UniqueArray<ControlValue>

    /// Creates a new control value table with the specified capacity.
    ///
    /// - Parameter capacity: Number of control value entries to allocate
    init(capacity: UInt16) {
      rawValues = .init(repeating: .init(fUnits: 0), count: Int(capacity))
      controlValueCutIn = kDefaultControlValueCutIn  // default is "17/16 pixels"
    }

    /// Creates an empty control value table.
    init() {
      rawValues = .init(capacity: 0)
      controlValueCutIn = 0
    }

    /// Sets the control values from a span of `F26Dot6` bit patterns.
    ///
    /// - Parameter newValues: New control values to set
    mutating func setValues(bitPatterns newValues: Span<Int32>) {
      assert(newValues.count == rawValues.count)
      rawValues.removeAll()
      for index in newValues.indices {
        rawValues.append(.init(fUnits: .init(bitPattern: newValues[index])))
      }
    }

    /// Sets the control values from a span of values.
    ///
    /// - Parameter newValues: New control values to set
    mutating func setValues(_ newValues: Span<F26Dot6>) {
      assert(newValues.count == rawValues.count)
      rawValues.removeAll()
      for index in newValues.indices {
        rawValues.append(.init(fUnits: newValues[index]))
      }
    }

    var values: [ControlValue] {
      Array(copying: rawValues.span)
    }

    /// Resets control value table parameters to specified values.
    ///
    /// - Parameter parameters: Configuration parameters to apply
    mutating func reset(_ parameters: Parameters) {
      controlValueCutIn = parameters.controlValueCutIn
      singleWidthCutIn = parameters.singleWidthCutIn
      singleWidthValue = parameters.singleWidthValue
    }

    /// Reads a control value at the specified index.
    ///
    /// - Parameter index: Index of the control value to read
    /// - Returns: The control value at the specified index
    func readEntry(_ index: Int) throws(InterpreterError) -> ControlValue {
      guard rawValues.indices.contains(index) else {
        throw .cvtLocationOutOfBounds
      }
      return rawValues[index]
    }

    /// Writes a control value at the specified index.
    ///
    /// - Parameters:
    ///   - entry: Control value to write
    ///   - index: Index where to write the control value
    mutating func writeEntry(_ entry: ControlValue, atIndex index: Int) throws(InterpreterError) {
      guard rawValues.indices.contains(index) else {
        throw .cvtLocationOutOfBounds
      }
      rawValues[index] = entry
    }
  }

  /// A control value used for distance regularization in TrueType hinting.
  ///
  /// Represents a distance measurement that can be scaled and applied
  /// during glyph outline processing.
  struct ControlValue: BitwiseCopyable {
    /// Distance value in font units.
    var fUnits: F26Dot6

    /// Returns the control value stretched by a scaling factor.
    ///
    /// - Parameter scale: Scaling factor to apply
    /// - Returns: Stretched distance value
    func stretched(by scale: F16Dot16) -> F26Dot6 {
      if scale == 1 { fUnits } else { fUnits.mixedMulRoundingToNearestOrUp(scale) }
    }
  }
}
