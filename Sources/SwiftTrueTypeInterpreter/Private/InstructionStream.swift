extension SwiftTrueTypeInterpreter {
  /// Manages execution state and navigation through TrueType hinting program instructions.
  ///
  /// Provides sequential access to instructions with support for jumps, loops, and different
  /// stream types (programs, functions, patches). Tracks current position and handles
  /// iteration control for instruction execution.
  struct InstructionStream: ~Copyable {
    /// Type of instruction stream being executed.
    enum StreamType: Equatable {
      /// Main hinting program stream.
      case program
      /// Function definition stream with function ID.
      case function(Int32)
      /// Instruction patch stream with opcode.
      case patch(UInt8)
    }

    /// Type of this instruction stream.
    let type: StreamType
    /// Definition containing the instruction data and range.

    let definition: Definition

    /// Current position within the instruction stream.
    fileprivate(set) var index: Int

    /// Number of remaining loop iterations.
    fileprivate(set) var loop: Int

    /// Creates a new instruction stream.
    ///
    /// - Parameters:
    ///   - type: The type of the stream.
    ///   - definition: The definition of the stream to interpret.
    ///   - loop: The number of times the instructions should be run before the stream completes.
    ///            Only `LOOPCALL` sets `count > 1`.
    init(type: StreamType, definition: Definition, loop: Int = 1) {
      self.type = type
      self.definition = definition
      self.index = definition.range.lowerBound
      self.loop = loop
    }

    /// Starting index of the instruction stream.
    @inline(always)
    var startIndex: Int { definition.range.lowerBound }

    /// Ending index of the instruction stream.
    @inline(always)
    var endIndex: Int { definition.range.upperBound }

    /// Whether the stream has reached its end.
    @inline(always)
    var isAtEnd: Bool {
      index >= endIndex
    }

    /// Restarts the stream for the next loop iteration.
    ///
    /// Decrements the loop count and resets the index to the start if more iterations remain.
    ///
    /// - Returns: `true` if the stream was restarted successfully, `false` if no more loops remain
    mutating func restart() -> Bool {
      loop &-= 1
      if loop > 0 {
        index = startIndex
        return index < endIndex
      }
      return false
    }

    /// Performs a jump operation, skipping the next `n` instructions, counting from the opcode at the previous position.
    ///
    /// This function allows seeking to the end of the stream, which ends the current loop.
    /// `n` may be negative.
    mutating func jump(_ n: Int32) throws(InterpreterError) {
      assert(index > startIndex)
      let (newIndex, overflow) = Int(n).addingReportingOverflow(index &- 1)
      guard !overflow, newIndex >= startIndex, newIndex <= endIndex else {
        // Unconditionally end the stream in case a `catch` in the caller keeps this instance alive
        index = endIndex
        throw .ranOffEndOfInstructions
      }
      index = newIndex
    }

    /// Returns the index for the next instruction in the stream.
    ///
    /// Only the main interpreter loop should set `looping = true`. Other callers (`NPUSHB`, `seek(after:)`, etc.) should
    /// only be concerned with the current iteration of the loop.
    ///
    /// - Parameter looping: Whether to allow automatic restart when reaching stream end
    /// - Returns: Index of next instruction, or `nil` if stream is exhausted
    @inline(always)
    mutating func next(looping: Bool = false) -> Int? {
      guard !isAtEnd || looping && restart() else {
        return nil
      }
      defer { index &+= 1 }
      return index
    }

    /// Skips the next `n` opcodes. `n` must be nonnegative.
    ///
    /// This function allows seeking to the end of the stream, which ends the current loop.
    ///
    /// - Parameter count: Number of opcodes to skip (must be >= 0)
    mutating func skip(_ count: Int) throws(InterpreterError) {
      assert(count >= 0)
      let (newIndex, overflow) = index.addingReportingOverflow(count)
      guard !overflow, newIndex <= endIndex else {
        // Unconditionally end the stream in case a `catch` in the caller keeps this instance alive
        index = endIndex
        throw .ranOffEndOfInstructions
      }
      index = newIndex
    }

    /// Advances stream by the specified count and returns the consumed range.
    ///
    /// - Parameter count: Number of instructions to consume
    /// - Returns: Range representing the consumed instruction indices
    mutating func next(count: Int) throws(InterpreterError) -> Range<Int> {
      let start = index
      try skip(count)
      // SAFETY: Bounds guaranteed by `skip()` (control flow thrown on violation)
      return unsafe .init(uncheckedBounds: (start, index))
    }
  }
}
