extension SwiftTrueTypeInterpreter {
  /// Configuration parameters for the TrueType interpreter.
  struct Parameters {
    /// Threshold for control value cut-in operations.
    var controlValueCutIn: F26Dot6 = kDefaultControlValueCutIn

    /// Threshold for single width cut-in operations.
    var singleWidthCutIn: F26Dot6 = 0

    /// Reference value for single width calculations.
    var singleWidthValue: ControlValue = .init(fUnits: 0)

    /// Whether to automatically flip direction of vectors.
    var autoFlip: Bool = true

    /// Base value for delta exception calculations.
    var deltaBase: Int16 = 9

    /// Shift value for delta exception calculations.
    var deltaShift: Int16 = 3

    /// Instruction control flags.
    var instructControl: GraphicsState.InstructControl = .init()

    /// Minimum distance for point movements.
    var minimumDistance: F26Dot6 = 1

    /// Current rounding state configuration.
    var roundState: GraphicsState.RoundState = .rtg

    /// Scan conversion control settings.
    var scanControl: GraphicsState.ScanControl = .init()

    /// Updates parameters from CVT and graphics state.
    ///
    /// - Parameters:
    ///   - cvt: Control value table to read from
    ///   - gs: Graphics state to read from
    mutating func update(cvt: borrowing ControlValueTable, gs: GraphicsState) {
      controlValueCutIn = cvt.controlValueCutIn
      singleWidthCutIn = cvt.singleWidthCutIn
      singleWidthValue = cvt.singleWidthValue

      autoFlip = gs.autoFlip
      deltaBase = gs.deltaBase
      deltaShift = gs.deltaShift
      instructControl = gs.instructControl
      minimumDistance = gs.minimumDistance
      roundState = gs.roundState
      scanControl = gs.scanControl
    }
  }
}
