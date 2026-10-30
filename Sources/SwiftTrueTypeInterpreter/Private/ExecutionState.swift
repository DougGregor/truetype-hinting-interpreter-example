extension SwiftTrueTypeInterpreter {
  /// The location of the opcodes for an executable routine.
  struct Definition {
    /// The program that contains this routine.
    let program: ProgramIdentifier

    /// The range of opcode indices in the program corresponding to this routine.
    let range: Range<Int>

    /// The undefined routine, containing no opcodes.
    static var undefined: Self {
      // No FDEF or IDEF can ever be at position 0 in Fpgm
      Self(program: .fpgm, range: 0..<0)
    }

    /// Whether this definition represents an undefined routine.
    var isUndefined: Bool { program == .fpgm && range.isEmpty && range.lowerBound == 0 }
  }

  /// The library of the opcodes of all programs.
  struct Code: ~Copyable, ~Escapable {
    /// The fpgm program.
    ///
    /// Once filled out, this field must remain the same for all subsequent prep and glyf executions.
    var fpgm: Span<UInt8>

    /// The prep program, set during prep execution.
    ///
    /// This is empty during fpgm execution. Once set, this must hold the same data for all subsequent glyf executions.
    var prep: Span<UInt8>

    /// The current glyf program.
    /// This is empty during fpgm and prep runs, and it may vary between glyf executions.
    var glyf: Span<UInt8>

    /// Creates a new code library with the specified program data.
    ///
    /// - Parameters:
    ///   - fpgm: Font program data
    ///   - prep: Control value program data
    ///   - glyf: Glyph program data
    @_lifetime(copy fpgm, copy prep, copy glyf)
    init(fpgm: Span<UInt8>, prep: Span<UInt8>, glyf: Span<UInt8>) {
      self.fpgm = fpgm
      self.prep = prep
      self.glyf = glyf
    }

    /// Returns the opcodes for the specified program.
    ///
    /// - Parameter program: Program identifier to retrieve opcodes for
    /// - Returns: Span containing the program's opcodes
    @_lifetime(copy self)
    func opcodes(of program: ProgramIdentifier) -> Span<UInt8> {
      switch program {
      case .fpgm: fpgm
      case .prep: prep
      case .glyf: glyf
      }
    }
  }

  /// Manages the execution context and state for TrueType hinting programs.
  ///
  /// Handles instruction and function definitions, call stack management, and program navigation.
  /// Maintains the current execution frame and provides access to program opcodes.
  struct ExecutionState: ~Copyable, ~Escapable {
    typealias Definition = SwiftTrueTypeInterpreter.Definition
    typealias StreamType = SwiftTrueTypeInterpreter.InstructionStream.StreamType
    typealias InstructionStream = SwiftTrueTypeInterpreter.InstructionStream
    typealias InterpreterError = SwiftTrueTypeInterpreter.InterpreterError
    typealias Opcode = SwiftTrueTypeInterpreter.Opcode
    typealias ProgramIdentifier = SwiftTrueTypeInterpreter.ProgramIdentifier

    /// The program that is currently being executed.
    let program: ProgramIdentifier

    /// Code library containing all program opcodes.
    let code: Code

    /// All currently defined instructions.
    private(set) var idefs: IDefs

    /// All currently defined functions.
    private(set) var fdefs: FDefs

    /// The current call stack below the current frame.
    var callStack: UniqueArray<InstructionStream>

    /// The current frame being executed.
    var topFrame: InstructionStream

    /// The opcodes of the entire program that contains the current frame.
    var opcodes: Span<UInt8>

    /// Creates a new execution state for the specified program.
    ///
    /// - Parameters:
    ///   - program: Program identifier to execute
    ///   - code: Code library containing program opcodes
    ///   - idefs: Instruction definitions
    ///   - fdefs: Function definitions
    @_lifetime(copy code)
    init(
      program: ProgramIdentifier,
      code: consuming Code,
      idefs: consuming IDefs,
      fdefs: consuming FDefs,
    ) {
      self.code = code
      self.program = program
      self.idefs = idefs
      self.fdefs = fdefs
      self.callStack = .init(capacity: SwiftTrueTypeInterpreter.kMaxAllowedRecursivity)
      self.opcodes = self.code.opcodes(of: program)
      self.topFrame = .init(type: .program, definition: .init(program: program, range: opcodes.indices))
    }

    /// Exports instruction and function definitions to external storage.
    ///
    /// Used after a program is complete, so definitions can be reused in the next program.
    ///
    /// - Parameters:
    ///   - idefs: Storage for instruction definitions (output parameter)
    ///   - fdefs: Storage for function definitions (output parameter)
    @_lifetime(self: copy self)
    mutating func export(idefs: inout IDefs, fdefs: inout FDefs) {
      idefs = exchange(&self.idefs, with: .null)
      fdefs = exchange(&self.fdefs, with: .null)
    }

    /// Returns the definition for the specified stream type.
    ///
    /// - Parameter streamType: Type of stream to get definition for
    /// - Returns: Definition containing program and range information
    func definition(of streamType: StreamType) -> Definition {
      switch streamType {
      case .program:
        Definition(program: program, range: code.opcodes(of: program).indices)
      case .function(let f):
        fdefs.lookup(identifier: f)
      case .patch(let i):
        idefs.lookup(opcode: i)
      }
    }

    // MARK: Instruction definitions

    /// Reads and defines an instruction definition from the current stream.
    ///
    /// - Parameter opcode: Opcode value to define
    @_lifetime(self: copy self)
    mutating func readIDEF(opcode: UInt8) throws(InterpreterError) {
      let range = try consumeUntilENDF()
      assert(opcodes.indices.contains(range))
      try idefs.define(opcode: opcode, as: Definition(program: program, range: range))
    }

    /// Instruction definitions.
    struct IDefs: ~Copyable {
      /// All current instruction definitions.
      /// Indexed by opcode (Eint8); always fully initialized with empty definitions.
      private var _storage: UniqueArray<Definition>

      /// The number of custom instruction definitions.
      private(set) var count: Int

      /// Maximum number of instruction definitions allowed.
      let capacity: Int

      /// Creates a new instruction definitions container.
      ///
      /// - Parameter capacity: Maximum number of definitions allowed
      init(capacity: Int) {
        self._storage = .init(repeating: .undefined, count: 1 << UInt8.bitWidth)
        self.count = 0
        self.capacity = capacity
      }

      /// True empty placeholder — `lookup`/`define` on this instance is undefined.
      /// Used only as a swap-out target during `exchange(&self, with: .null)`.
      private init(_emptyPlaceholder: Void) {
        self._storage = .init(capacity: 0)
        self.count = 0
        self.capacity = 0
      }

      /// Empty instruction definitions container.
      static var null: Self { Self(_emptyPlaceholder: ()) }

      /// Looks up the definition for the specified opcode.
      ///
      /// - Parameter opcode: Opcode to look up
      /// - Returns: Definition for the opcode, or undefined if not found
      @inline(always)
      func lookup(opcode: UInt8) -> Definition {
        _storage[Int(opcode)]
      }

      /// Defines or redefines an instruction opcode.
      ///
      /// - Parameters:
      ///   - opcode: Opcode to define
      ///   - newDefinition: Definition to associate with the opcode
      mutating func define(opcode: UInt8, as newDefinition: Definition) throws(InterpreterError) {
        let index = Int(opcode)
        let existingDefinition = _storage[index]
        assert(newDefinition.program != .glyf)  // Ruled out at a higher level
        if existingDefinition.isUndefined {
          assert(count >= 0)
          guard count < capacity &+ SwiftTrueTypeInterpreter.kMaxInstructionDefsSafeMargin else {
            throw .maxpLimitExceeded
          }
          count += 1
        }
        _storage[index] = newDefinition
      }
    }

    // MARK: Function definitions

    /// Reads and defines a function definition from the current stream.
    ///
    /// - Parameter identifier: Function identifier to define
    @_lifetime(self: copy self)
    mutating func readFDEF(identifier: Int32) throws(InterpreterError) {
      // FDEFs in function/instruction bodies were filtered out at definition time
      assert(topFrame.type == .program)

      let range = try consumeUntilENDF()
      assert(opcodes.indices.contains(range))
      try fdefs.define(identifier: identifier, as: Definition(program: program, range: range))
    }

    /// Function definitions.
    struct FDefs: ~Copyable {
      /// All current instruction definitions.
      /// Indexed by identifier (Int32), up to the limit in maxp.
      private var _storage: UniqueArray<Definition>

      /// Creates a new function definitions container.
      ///
      /// - Parameter capacity: Maximum number of function definitions allowed
      init(capacity: Int) {
        _storage = .init(repeating: .undefined, count: capacity)
      }

      /// Empty function definitions container.
      static var null: Self { Self(capacity: 0) }

      /// Maximum number of function definitions allowed.
      var capacity: Int { _storage.capacity }

      /// Looks up the definition for the specified function identifier.
      ///
      /// - Parameter identifier: Function identifier to look up
      /// - Returns: Definition for the function, or undefined if not found
      @inline(always)
      func lookup(identifier: Int32) -> Definition {
        let identifier = Int(identifier)
        guard _storage.indices.contains(identifier) else {
          return .undefined
        }
        return _storage[identifier]
      }

      /// Defines or redefines a function identifier.
      ///
      /// - Parameters:
      ///   - identifier: Function identifier to define
      ///   - definition: Definition to associate with the identifier
      mutating func define(identifier: Int32, as definition: Definition) throws(InterpreterError) {
        assert(definition.program != .glyf)  // Should have already been ruled out before
        let identifier = Int(identifier)
        // Bincompat: FDEF/CALL/LOOPCALL with a function index exceeding the maxp limit by less than
        // kMaxFunctionDefsSafeMargin are ignored.
        guard identifier >= 0,
              identifier < _storage.count &+ SwiftTrueTypeInterpreter.kMaxFunctionDefsSafeMargin
        else {
          throw .maxpLimitExceeded
        }
        if identifier >= _storage.count {
          return
        }
        _storage[identifier] = definition
      }
    }

    // MARK: Interpreter-specific logic

    /// Returns the opcode at the previous position in the current frame.
    ///
    /// - Returns: Previous opcode, or `nil` if at start of frame
    func previousOpcode() -> UInt8? {
      guard topFrame.index > topFrame.startIndex else { return nil }
      return opcodes[topFrame.index &- 1]
    }

    /// Returns the next opcode in the current frame.
    ///
    /// - Parameter looping: Whether to allow automatic restart for looped frames
    /// - Returns: Next opcode, or `nil` if frame is exhausted
    @_lifetime(self: copy self)
    @inline(always)
    mutating func nextOpcode(looping: Bool = false) -> UInt8? {
      guard let position = topFrame.next(looping: looping) else {
        return nil
      }
      return opcodes[position]
    }

    /// Returns the next sequence of opcodes from the current frame.
    ///
    /// - Parameter count: Number of opcodes to retrieve
    /// - Returns: Span containing the requested opcodes
    @_lifetime(self: copy self)
    @_lifetime(copy self)
    mutating func nextOpcodes(count: Int) throws(InterpreterError) -> Span<UInt8> {
      let range = try topFrame.next(count: count)
      return opcodes.extracting(range)
    }

    /// Pops the current frame from the call stack and restores the previous frame.
    ///
    /// - Returns: `true` if a frame was popped, `false` if call stack was empty
    mutating func popFrame() -> Bool {
      assert(topFrame.isAtEnd && topFrame.loop == 0)
      guard !callStack.isEmpty else { return false }
      topFrame = callStack.removeLast()
      self.opcodes = code.opcodes(of: topFrame.definition.program)
      return true
    }

    /// Push the current frame onto the interpreted program's call stack and replace it with
    /// the definition of the given reference, to be called `count` times.
    ///
    /// Must be the last call inside the instruction loop body.
    @_lifetime(self: copy self)
    @inline(always)
    mutating func call(
      type: StreamType,
      loop count: Int = 1
    ) throws(InterpreterError) {
      assert(type != .program)
      let definition = definition(of: type)
      guard !definition.range.isEmpty else { return }
      guard count > 0 else { return }
      if callStack.count >= SwiftTrueTypeInterpreter.kMaxAllowedRecursivity {
        throw .callStackTooDeep
      }
      self.opcodes = code.opcodes(of: definition.program)
      callStack.append(
        exchange(&topFrame, with: InstructionStream(type: type, definition: definition, loop: count))
      )
    }

    /// Returns all instructions from the current position up until the next `ENDF`, accounting for `PUSH` operands.
    /// The `ENDF` will not be in the returned slice, but it will be consumed from the stream.
    @_lifetime(self: copy self)
    @inline(always)
    mutating func consumeUntilENDF() throws(InterpreterError) -> Range<Int> {
      assert(previousOpcode() == Opcode.FDEF.rawValue || previousOpcode() == Opcode.IDEF.rawValue)
      let start = topFrame.index
      while let op = nextOpcode() {
        switch op {
        case Opcode.ENDF.rawValue:
          assert(start < topFrame.index)
          return start..<(topFrame.index &- 1)
        case Opcode.FDEF.rawValue, Opcode.IDEF.rawValue:
          throw .definitionsCannotBeNested
        default:
          try skipPushOps(op)
        }
      }
      throw .ranOffEndOfInstructions
    }

    /// Seeks to the end of a conditional block, optionally stopping at ELSE.
    ///
    /// - Parameter stopOnElse: Whether to stop when encountering an ELSE instruction
    @_lifetime(self: copy self)
    @inline(always)
    mutating func seekAfterConditionalBlock(stopOnElse: Bool) throws(InterpreterError) {
      assert(previousOpcode() == Opcode.IF.rawValue || previousOpcode() == Opcode.ELSE.rawValue)
      var level = 1  // Nested conditional depth
      while let op = nextOpcode() {
        switch op {
        case Opcode.EIF.rawValue:
          level &-= 1
          if level == 0 { return }
        case Opcode.IF.rawValue:
          level &+= 1
        case Opcode.ELSE.rawValue:
          // this permits multiple ELSEs inside the ELSE block we're skipping over,
          // which feels malformed but matches previously-shipped behaviour.
          if level == 1, stopOnElse { return }
        default:
          try skipPushOps(op)
        }
      }
      throw .ranOffEndOfInstructions
    }

    /// Skips operands for PUSH instructions based on the opcode.
    ///
    /// - Parameter op: Opcode to check for PUSH instruction variants
    @_lifetime(self: copy self)
    @inline(always)
    mutating func skipPushOps(_ op: UInt8) throws(InterpreterError) {
      let bytesPerWord = 2
      switch op {
      case Opcode.PUSHB.range:
        try topFrame.skip(Opcode.PUSHB.decodeCount(from: op))
      case Opcode.PUSHW.range:
        try topFrame.skip(Opcode.PUSHW.decodeCount(from: op) &* bytesPerWord)
      case Opcode.NPUSHB.rawValue:
        guard let i = nextOpcode() else { throw .ranOffEndOfInstructions }
        try topFrame.skip(Int(i))
      case Opcode.NPUSHW.rawValue:
        guard let i = nextOpcode() else { throw .ranOffEndOfInstructions }
        try topFrame.skip(Int(i) &* bytesPerWord)
      default:
        break
      }
    }
  }
}
