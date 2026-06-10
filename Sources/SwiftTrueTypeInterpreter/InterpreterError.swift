extension SwiftTrueTypeInterpreter {
  /// Errors that can occur during TrueType hinting program execution.
  public enum InterpreterError: Error, Equatable {
    /// Arithmetic operation resulted in overflow or invalid result.
    case arithmeticError

    /// Function call nesting exceeded maximum allowed depth.
    case callStackTooDeep

    /// Attempted to call undefined function.
    case calledFunctionNotDefined

    /// CVT table index is out of bounds.
    case cvtLocationOutOfBounds

    /// Function or instruction definitions cannot be nested.
    case definitionsCannotBeNested

    /// Function or instruction definitions not permitted in glyph programs.
    case definitionsNotAllowedInGlyf

    /// Encountered unrecognized or invalid instruction opcode.
    case illegalInstruction

    /// Internal interpreter state error.
    case internalError

    /// Attempted to access glyph zone when unavailable.
    case invalidAccessToGlyphZone

    /// Attempted to access twilight zone when unavailable.
    case invalidAccessToTwilightZone

    /// Instruction operand value is invalid.
    case invalidOperand

    /// Jump instruction target is out of bounds.
    case jumpOutOfBounds

    /// Maximum profile table limits exceeded.
    case maxpLimitExceeded

    /// No hinting program instructions provided for execution.
    case noInstructionsProvided

    /// Point index does not exist.
    case noSuchPoint

    /// Contour index does not exist.
    case noSuchContour

    /// Instruction pointer advanced beyond end of program.
    case ranOffEndOfInstructions

    /// Stack depth exceeded maximum limit.
    case stackDepthExceedsLimit

    /// Attempted to pop from empty stack.
    case stackUnderflow

    /// Storage area index is out of bounds.
    case storageLocationOutOfBounds

    /// Mismatched IF/ELSE/EIF conditional structure.
    case unbalancedIF_ELSE_EIF

    /// ENDF instruction without matching function definition.
    case unexpectedENDF
  }
}
