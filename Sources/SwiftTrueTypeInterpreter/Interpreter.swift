internal import BasicContainers
internal import ContainersPreview
import Darwin

/// TrueType hinting interpreter.
public class SwiftTrueTypeInterpreter {
  static let kMaxFunctionDefsSafeMargin = 6
  static let kMaxInstructionDefsSafeMargin = 4
  static let kMaxAllowedRecursivity = 64
  static let kFairDiceRoll: UInt32 = 17

  /// Program types that can be executed by the interpreter.
  enum ProgramIdentifier {
    /// Font program (fpgm table).
    case fpgm
    /// Control value program (prep table).
    case prep
    /// Glyph program (glyf table).
    case glyf
  }

  /// Interpreter execution state and data.
  struct State: ~Copyable, ~Escapable {
    var executionState: ExecutionState

    /// Sub-state containing graphics state and related data.
    struct Substate: ~Copyable {
      var gs: GraphicsState
      let _maxp: UniqueBox<sfntMaxProfileTable>
      var cvt: ControlValueTable
      let scaleFactors: ScaleFactors
      var stack: Stack

      var maxp: sfntMaxProfileTable {  // _read accessor avoids a Swift compiler bug copying the noncopyable storage.
        _read { yield _maxp.value }
      }
    }

    var substate: Substate

    var gs: GraphicsState {
      _read { yield substate.gs }
      @_lifetime(self: copy self)
      _modify { yield &substate.gs }
    }

    var maxp: sfntMaxProfileTable {
      _read { yield substate._maxp.value }
    }

    var cvt: ControlValueTable {
      _read { yield substate.cvt }
      @_lifetime(self: copy self)
      _modify { yield &substate.cvt }
    }

    var scaleFactors: ScaleFactors {
      _read { yield substate.scaleFactors }
    }

    var stack: Stack {
      _read { yield substate.stack }
      @_lifetime(self: copy self)
      _modify { yield &substate.stack }
    }

    var storageArea: StorageArea
    var variationCoord: RigidArray<F2Dot14>
    // Wrapping `Zone`s carry the lifetime of their exclusive borrow of the caller's
    // `fnt_ElementType`; empty `Zone`s are immortal. `State.init` composes both into `self`.
    var _twilightZone: Zone
    var _glyphZone: Zone
    var unscaledOutlineIsWrong: Bool

    @_lifetime(copy code, copy twilightZone, copy glyphZone)
    init(
      importing interp: SwiftTrueTypeInterpreter,
      program: ProgramIdentifier,
      code: consuming Code,
      twilightZone: consuming Zone,
      glyphZone: consuming Zone,
      unscaledOutlineIsWrong: Bool = false
    ) {
      self.executionState = .init(
        program: program,
        code: code,
        idefs: exchange(&interp._idefs, with: .null),
        fdefs: exchange(&interp._fdefs, with: .null)
      )
      self.substate = .init(
        gs: interp._gs,
        _maxp: .init(interp.maxp),
        cvt: exchange(&interp._cvt, with: .init()),
        scaleFactors: interp._scaleFactors,
        stack: .init()
      )
      self.storageArea = exchange(&interp._storageArea, with: .init())
      self.variationCoord = exchange(&interp.variationCoord, with: .init(capacity: 0))

      self._twilightZone = twilightZone
      self._glyphZone = glyphZone
      self.unscaledOutlineIsWrong = unscaledOutlineIsWrong
    }

    @_lifetime(self: copy self)
    mutating func export(to interp: SwiftTrueTypeInterpreter) {
      swap(&interp._stack, &substate.stack)
      self.executionState.export(idefs: &interp._idefs, fdefs: &interp._fdefs)
      interp._gs = gs
      swap(&interp._cvt, &substate.cvt)
      swap(&interp._storageArea, &storageArea)
      swap(&interp.variationCoord, &variationCoord)
    }

    mutating func rollbackGlyphZone() {
      if self._glyphZone.isPresent { self._glyphZone.rollback() }
    }

    @_lifetime(self: copy self)
    @inline(always) @_transparent
    mutating func effectiveCVTScale() -> F16Dot16 {
      substate.effectiveCVTScale()
    }

    // Explicit closure-taking borrow function: works around lifetime-dependence inference
    // limitations for borrows of mutable ~Copyable storage.
    @inline(always) @_transparent
    fileprivate func borrowZone<R>(
      type: ZoneType,
      _ op: (borrowing Zone) throws(InterpreterError) -> R
    ) throws(InterpreterError) -> R {
      switch type {
      case .glyph:
        guard self._glyphZone.isPresent else { throw .invalidAccessToGlyphZone }
        return try op(self._glyphZone)
      case .twilight:
        guard self._twilightZone.isPresent else { throw .invalidAccessToTwilightZone }
        return try op(self._twilightZone)
      }
    }

    @_lifetime(self: copy self)
    @inline(always) @_transparent
    fileprivate mutating func withZP<T>(
      type: ZoneType,
      _ op: (inout Zone, inout Self.Substate) throws(InterpreterError) -> T
    ) throws(InterpreterError) -> T {
      switch type {
      case .glyph:
        guard self._glyphZone.isPresent else { throw .invalidAccessToGlyphZone }
        return try op(&self._glyphZone, &self.substate)
      case .twilight:
        guard self._twilightZone.isPresent else { throw .invalidAccessToTwilightZone }
        return try op(&self._twilightZone, &self.substate)
      }
    }

    @_lifetime(self: copy self)
    @inline(always) @_transparent
    fileprivate mutating func withZP0<T>(
      _ op: (inout Zone, inout Substate) throws(InterpreterError) -> T
    ) throws(InterpreterError) -> T {
      try withZP(type: gs.zp0, op)
    }

    @_lifetime(self: copy self)
    @inline(always) @_transparent
    fileprivate mutating func withZP1<T>(
      _ op: (inout Zone, inout Substate) throws(InterpreterError) -> T
    ) throws(InterpreterError) -> T {
      try withZP(type: gs.zp1, op)
    }

    @_lifetime(self: copy self)
    @inline(always) @_transparent
    fileprivate mutating func withZP2<T>(
      _ op: (inout Zone, inout Substate) throws(InterpreterError) -> T
    ) throws(InterpreterError) -> T {
      try withZP(type: gs.zp2, op)
    }

    @_lifetime(self: copy self)
    mutating func loop(dispatch: borrowing [JumpTableFunc]) throws(InterpreterError) {
      repeat {
        while let opcode = executionState.nextOpcode(looping: true) {
          try dispatch[Int(opcode)](&self, opcode)
        }
      } while executionState.popFrame()
    }
  }

  private let maxp: sfntMaxProfileTable

  /// Creates a new interpreter instance.
  ///
  /// - Parameters:
  ///   - maxp: Maximum profile table from the font
  ///   - cvtCount: Number of entries in the control value table
  public init(maxp: sfntMaxProfileTable, cvtCount: UInt16) {
    self.maxp = maxp

    // The properties below would be declared `lazy`, but `lazy` currently inhibits uniqueness optimizations.
    _stack = .init()
    _idefs = .init(capacity: .init(maxp.maxInstructionDefs))
    _fdefs = .init(capacity: .init(maxp.maxFunctionDefs))
    _storageArea = .init(count: UInt16(maxp.maxStorage))
    _cvt = .init(capacity: cvtCount)
    variationCoord = .init(capacity: 0)
  }

  private var parameters: Parameters = .init()

  /// Exports interpreter parameters to parameter block.
  ///
  /// - Parameter parBlock: Parameter block to update
  /// - Returns: Whether parameters should be written back to default block
  @discardableResult
  public func export(
    parBlock p: inout fnt_ParameterBlock
  ) -> Bool {
    p.wTCI = _cvt.controlValueCutIn.bitPattern
    p.sWCI = _cvt.singleWidthCutIn.bitPattern
    p.scaledSW = _cvt.singleWidthValue.fUnits.bitPattern
    p.scanControl = .init(bitPattern: _gs.scanControl.rawValue)
    p.instructControl = .init(_gs.instructControl.rawValue)
    p.minimumDistance = _gs.minimumDistance.bitPattern
    p.period45 = F2Dot30(_gs.roundState.period45).bitPattern
    p.period = .init(_gs.roundState.period.bitPattern)
    p.phase = .init(_gs.roundState.phase.bitPattern)
    p.threshold = .init(_gs.roundState.threshold.bitPattern)
    p.deltaBase = _gs.deltaBase
    p.deltaShift = _gs.deltaShift
    p.autoFlip = (_gs.autoFlip ? 1 : 0)
    return !_gs.instructControl.contains(.default)
  }

  private var _stack: Stack
  public private(set) var _gs: GraphicsState = .init()
  private var _idefs: ExecutionState.IDefs
  private var _fdefs: ExecutionState.FDefs
  private var _storageArea: StorageArea

  private var _cvt: ControlValueTable  // set by caller before runPrep
  /// Sets control value table from external data.
  ///
  /// - Parameter values: `F26Dot6` bit patterns of the CVT entries
  public func setCVT(_ values: Span<Int32>) {
    _cvt.setValues(bitPatterns: values)
  }

  var variationCoord: RigidArray<F2Dot14>
  /// Sets variation coordinates for font variations.
  ///
  /// - Parameter coords: `F2Dot14` bit patterns of the coordinates
  public func setVariationCoord(_ coords: Span<CShort>) {
    variationCoord.removeAll()
    if variationCoord.capacity < coords.count {
      variationCoord.reallocate(capacity: coords.count)
    }
    for index in coords.indices {
      variationCoord.append(F2Dot14(bitPattern: coords[index]))
    }
  }

  /// Sets `count` variation coordinates, all zero.
  public func setNullVariationCoord(count: Int) {
    variationCoord.removeAll()
    if variationCoord.capacity < count {
      variationCoord.reallocate(capacity: count)
    }
    for _ in 0..<max(count, 0) {
      variationCoord.append(.zero)
    }
  }

  public private(set) var _scaleFactors: ScaleFactors = .init()

  /// Sets scaling factors for the interpreter.
  ///
  /// - Parameters:
  ///   - xStretch: X-axis stretch factor (F16Dot16 format)
  ///   - yStretch: Y-axis stretch factor (F16Dot16 format)
  ///   - unitsPerEm: Font units per em
  ///   - pointSize: Target point size
  ///   - cvtScale: CVT scaling factor (F16Dot16 format)
  ///   - rotated: Whether transformation includes rotation
  ///   - stretched: Whether transformation includes stretching
  public func setScaleFactors(
    xStretch: Int32,  // F16Dot16
    yStretch: Int32,  // F16Dot16
    unitsPerEm: Int16,
    pointSize: Int32,
    cvtScale: Int32,  // F16Dot16
    isRotated rotated: Bool,
    isStretched stretched: Bool
  ) {
    _scaleFactors = .init(
      stretch: .init(x: .init(bitPattern: xStretch), y: .init(bitPattern: yStretch)),
      unitsPerEm: unitsPerEm,
      pointSize: pointSize,
      cvtScale: .init(bitPattern: cvtScale),
      isRotated: rotated,
      isStretched: stretched
    )
  }

  // MARK: - State inspection

  public func writeStorageArea(_ value: UInt32, at index: UInt32) throws(InterpreterError) {
    try _storageArea.write(value, at: index)
  }

  public func setCVTValues(_ values: [F26Dot6]) {
    _cvt.setValues(values.span)
  }

  public func stackView() -> [Int32] {
    Array(copying: _stack.items.span).reversed().map { $0.int32() }
  }

  public var graphicsState: GraphicsState {
    _gs
  }

  public var controlValueCutIn: F26Dot6 {
    _cvt.controlValueCutIn
  }

  public var singleWidthCutIn: F26Dot6 {
    _cvt.singleWidthCutIn
  }

  public var singleWidthValue: F26Dot6 {
    _cvt.singleWidthValue.fUnits
  }

  public func storageView() -> [Int32] {
    _storageArea.contents()
  }

  public func cvtView() -> [F26Dot6] {
    _cvt.values.map(\.fUnits)
  }

  private var readyForProgram: ProgramIdentifier = .fpgm

  // MARK: - Run entry points

  /// Runs TrueType programs (fpgm, prep, or glyf) with no zones.
  ///
  /// - Parameters:
  ///   - fpgm: Font program bytecode (empty if none)
  ///   - prep: Control value program bytecode (empty if none)
  ///   - glyf: Glyph program bytecode (empty if none)
  ///   - unscaledOutlineIsWrong: Whether unscaled outline needs correction
  ///   - parBlock: Parameter block for configuration
  public func runProgram(
    fpgm: Span<UInt8>,
    prep: Span<UInt8>,
    glyf: Span<UInt8>,
    unscaledOutlineIsWrong: Bool,
    parBlock: inout fnt_ParameterBlock
  ) throws {
    try run(
      fpgm: fpgm, prep: prep, glyf: glyf,
      twilightZone: .empty(.twilight), glyphZone: .empty(.glyph),
      unscaledOutlineIsWrong: unscaledOutlineIsWrong, parBlock: &parBlock)
  }

  /// Runs TrueType programs with a twilight zone only.
  ///
  /// See ``runProgram(fpgm:prep:glyf:unscaledOutlineIsWrong:parBlock:)``. The element must be
  /// valid: its counts accurate (`pointCount ≤ maxPointCount`, `contourCount ≤
  /// maxContourCount`) and its parallel arrays at least `maxPointCount` long (`sp` and `ep`:
  /// `maxContourCount`). Invalid elements are rejected with a precondition failure.
  public func runProgram(
    fpgm: Span<UInt8>,
    prep: Span<UInt8>,
    glyf: Span<UInt8>,
    twilightZone twilightElement: inout fnt_ElementType,
    unscaledOutlineIsWrong: Bool,
    parBlock: inout fnt_ParameterBlock
  ) throws {
    try run(
      fpgm: fpgm, prep: prep, glyf: glyf,
      twilightZone: .twilightZone(wrapping: &twilightElement), glyphZone: .empty(.glyph),
      unscaledOutlineIsWrong: unscaledOutlineIsWrong, parBlock: &parBlock)
  }

  /// Runs TrueType programs with a glyph zone only.
  ///
  /// See ``runProgram(fpgm:prep:glyf:twilightZone:unscaledOutlineIsWrong:parBlock:)`` for the
  /// requirements on the element.
  public func runProgram(
    fpgm: Span<UInt8>,
    prep: Span<UInt8>,
    glyf: Span<UInt8>,
    glyphZone glyphElement: inout fnt_ElementType,
    unscaledOutlineIsWrong: Bool,
    parBlock: inout fnt_ParameterBlock
  ) throws {
    try run(
      fpgm: fpgm, prep: prep, glyf: glyf,
      twilightZone: .empty(.twilight), glyphZone: .glyphZone(wrapping: &glyphElement),
      unscaledOutlineIsWrong: unscaledOutlineIsWrong, parBlock: &parBlock)
  }

  /// Runs TrueType programs with both a twilight and a glyph zone.
  ///
  /// See ``runProgram(fpgm:prep:glyf:twilightZone:unscaledOutlineIsWrong:parBlock:)`` for the
  /// requirements on the elements.
  public func runProgram(
    fpgm: Span<UInt8>,
    prep: Span<UInt8>,
    glyf: Span<UInt8>,
    twilightZone twilightElement: inout fnt_ElementType,
    glyphZone glyphElement: inout fnt_ElementType,
    unscaledOutlineIsWrong: Bool,
    parBlock: inout fnt_ParameterBlock
  ) throws {
    try run(
      fpgm: fpgm, prep: prep, glyf: glyf,
      twilightZone: .twilightZone(wrapping: &twilightElement),
      glyphZone: .glyphZone(wrapping: &glyphElement),
      unscaledOutlineIsWrong: unscaledOutlineIsWrong, parBlock: &parBlock)
  }

  private func run(
    fpgm: Span<UInt8>,
    prep: Span<UInt8>,
    glyf: Span<UInt8>,
    twilightZone: consuming Zone,
    glyphZone: consuming Zone,
    unscaledOutlineIsWrong: Bool,
    parBlock: inout fnt_ParameterBlock
  ) throws {
    let code = Code(fpgm: fpgm, prep: prep, glyf: glyf)
    let fpgmCount = fpgm.count
    let prepCount = prep.count
    let glyfCount = glyf.count

    if glyfCount > 0 {
      defer { export(parBlock: &parBlock) }
      try execute(
        .glyf,
        code: code,
        twilightZone: twilightZone,
        glyphZone: glyphZone,
        rollbackGlyphZoneOnError: true,
        unscaledOutlineIsWrong: unscaledOutlineIsWrong
      )
    } else if prepCount > 0 {
      assert(readyForProgram != .glyf, "attempt to run prep twice or after a glyf program")
      readyForProgram = .glyf
      defer {
        if !_gs.instructControl.contains(.default) {
          parameters.update(cvt: _cvt, gs: _gs)
        }
      }
      try execute(.prep, code: code, twilightZone: twilightZone, glyphZone: glyphZone)
    } else if fpgmCount > 0 {
      assert(readyForProgram == .fpgm, "attempt to run prep twice or after a glyf program")
      readyForProgram = .prep
      try execute(.fpgm, code: code, twilightZone: twilightZone, glyphZone: glyphZone)
    }
  }

  // MARK: - Interpreter loop
  private var running = false

  private func execute(
    _ program: ProgramIdentifier,
    code: consuming Code,
    twilightZone: consuming Zone,
    glyphZone: consuming Zone,
    rollbackGlyphZoneOnError: Bool = false,
    unscaledOutlineIsWrong: Bool = false
  ) throws(InterpreterError) {
    _gs.reset(parameters)
    _cvt.reset(parameters)

    do {
      var state = State(
        importing: self,
        program: program,
        code: code,
        twilightZone: twilightZone,
        glyphZone: glyphZone,
        unscaledOutlineIsWrong: unscaledOutlineIsWrong
      )
      defer {
        state.export(to: self)
      }
      assert(running == false, "no recursion allowed")
      defer { running = false }
      running = true
      do {
        try state.loop(dispatch: Self.dispatch)
      } catch {
        if rollbackGlyphZoneOnError {
          state.rollbackGlyphZone()
        }
        throw error
      }
    }
  }

  // MARK: - Opcodes

  @inline(always)
  static func impl_AA(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.pop()
  }

  @inline(always)
  static func impl_ABS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withOneF26Operand { $0 == .min ? .min : abs($0) })
  }

  @inline(always)
  static func impl_ADD(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoF26Operands(&+))
  }

  @inline(always)
  static func impl_ALIGNPTS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let p2index = try state.stack.pop().int()
    let p1index = try state.stack.pop().int()
    let p2 = try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
      try zone.hinted(at: p2index)
    }
    let p1 = try state.borrowZone(type: state.gs.zp1) { zone throws(InterpreterError) in
      try zone.hinted(at: p1index)
    }

    // Dotting against the projection vector gives the distance between those points along it.
    // This sets move to "roughly half" the distance (divided by 2, rounded towards 0),
    // and moves the points such that their final distance is exactly == dist. If we would lose
    // a bit to rounding when dividing by 2, that bit is given to the other point.
    let dist = state.gs.projectionVector.dot(p2 &- p1)
    let move = dist.dividedWithSaturation(by: 2, rounding: .down)

    try state.withZP1 { zp1, state throws(InterpreterError) in
      try zp1.check(against: state.maxp)
      let pt = try zp1.point(at: p1index)
      try state.gs.movePoint(in: &zp1, point: pt, delta: move)
    }

    try state.withZP0 { zp0, state throws(InterpreterError) in
      try zp0.check(against: state.maxp)
      let pt = try zp0.point(at: p2index)
      try state.gs.movePoint(in: &zp0, point: pt, delta: move &- dist)
    }
  }

  @inline(always)
  static func impl_ALIGNRP(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let rp0 = state.gs.rp0
    let p0 = try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
      try zone.hinted(at: rp0)
    }
    try state.withZP1 { zp1, state throws(InterpreterError) in
      try zp1.check(against: state.maxp)
      // Hoist projVec out of the loop: gs's _modify accessor blocks the compiler from
      // proving movePoint doesn't change it, so it would otherwise re-read each iteration.
      let projVec = state.gs.projectionVector
      while state.gs.loop > 0 {
        let index = try state.stack.pop().int()
        let pt = try zp1.point(at: index)
        let proj = 0 &- projVec.dot(zp1.hinted(pt) &- p0)
        try state.gs.movePoint(in: &zp1, point: pt, delta: proj)
        state.gs.loop -= 1
      }
      state.gs.loop = 1
    }
  }

  @inline(always)
  static func impl_AND(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands { $0 != 0 && $1 != 0 })
  }

  @inline(always)
  static func impl_CALL(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    // Old interpreter quietly returned if given a function that's
    // not yet defined. Only a function number outside the maximum
    // range causes an error.
    let f = try state.stack.pop().int32()
    guard f >= 0 else { throw .invalidOperand }
    guard f < state.executionState.fdefs.capacity + kMaxFunctionDefsSafeMargin else {
      throw .maxpLimitExceeded
    }
    try state.executionState.call(type: .function(f))
  }

  @inline(always)
  static func impl_CEILING(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withOneF26Operand { $0.roundingWithSaturation(.up) })
  }

  @inline(always)
  static func impl_CINDEX(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let index = try state.stack.pop().uint32()
    guard index != 0 else {
      // Instruction Set Reference says "A zero or negative value for k is an error", but
      // the FreeType implementation rewrites the top of the stack with zero (unless pedantic errors are enabled)
      try state.stack.push(.init(Int32(0)))
      return
    }
    let copiedElement = try state.stack.peek(indexBelowTop: index)
    try state.stack.push(copiedElement)
  }

  @inline(always)
  static func impl_CLEAR(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.stack = .init()
  }

  @inline(always)
  static func impl_DEBUG(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.pop()
  }

  @inline(always)
  static func impl_DELTAC1(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try deltaCVT(state: &state, phase: 0)
  }

  @inline(always)
  static func impl_DELTAC2(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try deltaCVT(state: &state, phase: kDeltaPhaseStride)
  }

  @inline(always)
  static func impl_DELTAC3(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try deltaCVT(state: &state, phase: 2 * kDeltaPhaseStride)
  }

  @inline(always)
  static func impl_DELTAP1(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try deltaMovePoint(state: &state, phase: 0)
  }

  @inline(always)
  static func impl_DELTAP2(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try deltaMovePoint(state: &state, phase: kDeltaPhaseStride)
  }

  @inline(always)
  static func impl_DELTAP3(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try deltaMovePoint(state: &state, phase: 2 * kDeltaPhaseStride)
  }

  @inline(always)
  static func impl_DEPTH(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(.init(state.stack.count))
  }

  @inline(always)
  static func impl_DIV(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(
      state.withTwoF26Operands { num, denom in
        if denom == 0 {
          // The old interpreter didn't fail, it just returned min/max
          (num < 0) ? F26Dot6.min : F26Dot6.max
        } else {
          num.dividedWithSaturation(by: denom, rounding: .towardZero)
        }
      }
    )
  }

  @inline(always)
  static func impl_DUP(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.stack.peek(indexBelowTop: 1))
  }

  @inline(always)
  static func impl_EIF(
    _: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    // This opcode's responsibilities are fully implemented by IF and ELSE.
    // For binary compatibility, an unexpected EIF is a no-op (previously-shipped behaviour).

  }

  @inline(always)
  static func impl_ELSE(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    // Encountering ELSE in the interpreter implies a preceding IF which we took;
    // seek to the instruction after this ELSE's matching EIF, skipping over any matching ELSEs.
    try state.executionState.seekAfterConditionalBlock(stopOnElse: false)
  }

  @inline(always)
  static func impl_ENDF(
    _: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    // This opcode's responsibilities are fully implemented by FDEF and IDEF.
    // Thus an unexpected ENDF is an error.
    throw .unexpectedENDF
  }

  @inline(always)
  static func impl_EQ(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands(==))
  }

  @inline(always)
  static func impl_EVEN(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let num = try state.stack.pop().f26dot6()
    let rounded = RoundState.rtg.round(num).integralPart
    try state.stack.push(StackElement(rounded.isMultiple(of: 2) ? 1 : 0 as Int32))
  }

  @inline(always)
  static func impl_FDEF(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    guard state.executionState.program != .glyf else {
      throw .definitionsNotAllowedInGlyf
    }

    // stack -> f: function identifier number (int32 in the range 0 through (n-1)
    // where n is specified in the 'maxp' table)
    // It's valid to redefine an already-defined function.
    let f = try state.stack.pop().int32()
    try state.executionState.readFDEF(identifier: f)
  }

  @inline(always)
  static func impl_FLIPOFF(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.autoFlip = false
  }

  @inline(always)
  static func impl_FLIPON(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.autoFlip = true
  }

  @inline(always)
  static func impl_FLIPPT(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.withZP0 { zone, state throws(InterpreterError) in
      try zone.check(against: state.maxp)
      for _ in 0..<max(0, state.gs.loop) {
        let index = try state.stack.pop().int()
        let pt = try zone.point(at: index)
        zone.toggleOnCurve(pt)
      }
      state.gs.loop = 1
    }
  }

  @inline(always)
  static func impl_FLIPRGOFF(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try fliprg(&state, onCurve: false)
  }

  @inline(always)
  static func impl_FLIPRGON(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try fliprg(&state, onCurve: true)
  }

  @inline(always)
  static func impl_FLOOR(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withOneF26Operand { $0.roundingWithSaturation(.down) })
  }

  @inline(always)
  static func impl_GC(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let originalPosition = Opcode.GC.immediate(for: instruction) == 1
    let index = try state.stack.pop().int()
    let value: F26Dot6 = try state.borrowZone(type: state.gs.zp2) { zone throws(InterpreterError) in
      let pt = try zone.point(at: index)
      if originalPosition {
        return state.gs.dualProjectionVector.dot(zone.scaled(pt))
      } else {
        return state.gs.projectionVector.dot(zone.hinted(pt))
      }
    }
    try state.stack.push(StackElement(value))
  }

  @inline(always)
  static func impl_GETDATA(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    var success = true
    switch try state.stack.pop().int() {
    case 1:  // randomFntGetData
      let n = try state.stack.pop().uint32()
      guard n != 0 else {
        throw .invalidOperand
      }
      try state.stack.push(StackElement(kFairDiceRoll % n))  // chosen by fair dice roll. guaranteed to be random

    default:
      success = false
    }
    try state.stack.push(StackElement(success ? 1 : 0 as Int32))
  }

  @inline(always)
  static func impl_GETINFO(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    struct SelectorBits: OptionSet {
      let rawValue: UInt32
      static let version = Self(rawValue: 1 << 0)
      static let rotated = Self(rawValue: 1 << 1)
      static let stretched = Self(rawValue: 1 << 2)
      static let variation = Self(rawValue: 1 << 3)
      static let verticalMetrics = Self(rawValue: 1 << 4)
    }
    struct ResultBits: OptionSet {
      let rawValue: UInt32
      static let rotated = Self(rawValue: 1 << 8)
      static let stretched = Self(rawValue: 1 << 9)
      static let variation = Self(rawValue: 1 << 10)
      static let verticalMetrics = Self(rawValue: 1 << 11)
    }
    let quickdrawGXInterpreterVersion = 7 as UInt32

    let selector = try SelectorBits(rawValue: state.stack.pop().uint32())
    var result = ResultBits()
    if selector.contains(.version) {
      result = ResultBits(rawValue: quickdrawGXInterpreterVersion)
    }
    if selector.contains(.rotated), state.scaleFactors.isRotated {
      result.insert(.rotated)
    }
    if selector.contains(.stretched), state.scaleFactors.isStretched {
      result.insert(.stretched)
    }
    if selector.contains(.variation) {
      result.insert(.variation)
    }
    if selector.contains(.verticalMetrics) {
      result.insert(.verticalMetrics)
    }

    try state.stack.push(StackElement(result.rawValue))
  }

  @inline(always)
  static func impl_GETVARIATION(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    if !state.variationCoord.isEmpty {
      var coords = RigidArray<F2Dot14>(capacity: 0)
      swap(&state.variationCoord, &coords)
      defer { swap(&coords, &state.variationCoord) }
      try coords.span._forEach { coord throws(InterpreterError) in
        try state.stack.push(.init(Int32(coord.bitPattern)))
      }
    } else {
      assert(instruction == Opcode.GETVARIATION.rawValue)
      try impl_InstructionPatch(&state, instruction)
    }
  }

  @inline(always)
  static func impl_GFV(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(StackElement(state.gs.freedomVector.x))
    try state.stack.push(StackElement(state.gs.freedomVector.y))
  }

  @inline(always)
  static func impl_GPV(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(StackElement(state.gs.projectionVector.x))
    try state.stack.push(StackElement(state.gs.projectionVector.y))
  }

  @inline(always)
  static func impl_GT(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands(>))
  }

  @inline(always)
  static func impl_GTEQ(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands(>=))
  }

  @inline(always)
  static func impl_IDEF(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    // stack -> opcode (Eint8)
    let opcode = try state.stack.pop().uint8()

    guard state.executionState.program != .glyf else {
      throw .definitionsNotAllowedInGlyf
    }
    try state.executionState.readIDEF(opcode: opcode)
  }

  @inline(always)
  static func impl_IF(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let condition = try state.stack.pop().uint32() != 0
    if !condition {
      // Seek to the first instruction after this IF's matching ELSE or EIF
      try state.executionState.seekAfterConditionalBlock(stopOnElse: true)
    }
  }

  @inline(always)
  static func impl_INSTCTRL(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let selector = try state.stack.pop().int()
    let value = try state.stack.pop().uint8()
    guard state.executionState.program == .prep else {
      return
    }
    switch selector {
    case 1:
      state.gs.instructControl.remove(.noGridFit)
      state.gs.instructControl.insert(.init(rawValue: value).intersection(.noGridFit))
    case 2:
      state.gs.instructControl.remove(.default)
      state.gs.instructControl.insert(.init(rawValue: value).intersection(.default))
    default:
      return
    }
  }

  @inline(always)
  static func impl_IP(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    guard state.gs.loop > 0 else {
      // not work to do
      state.gs.loop = 1
      return
    }

    let usesTwilightZone = state.gs.zp0 == .twilight || state.gs.zp1 == .twilight || state.gs.zp2 == .twilight
    if !usesTwilightZone, state.unscaledOutlineIsWrong { try state.correctUnscaledOutline() }

    let rp1 = state.gs.rp1
    let rp2 = state.gs.rp2
    let (ref1Hinted, ref1Scaled, ref1Original): (OutlineCoord, OutlineCoord, UnscaledCoord) =
      try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
        let p = try zone.point(at: rp1)
        return (zone.hinted(p), zone.scaled(p), zone.original(p))
      }
    let (ref2Hinted, ref2Scaled, ref2Original): (OutlineCoord, OutlineCoord, UnscaledCoord) =
      try state.borrowZone(type: state.gs.zp1) { zone throws(InterpreterError) in
        let p = try zone.point(at: rp2)
        return (zone.hinted(p), zone.scaled(p), zone.original(p))
      }

    let oldRange: F26Dot6
    let currentRange = state.gs.projectionVector.dot(ref2Hinted &- ref1Hinted)
    let dualRefPoint: OutlineCoord
    if usesTwilightZone {
      oldRange = state.gs.projectionVector.dot(ref2Scaled &- ref1Scaled)
      dualRefPoint = ref1Scaled
    } else {
      let unscaledRef1 = OutlineCoord(bitPattern: ref1Original)
      let unscaledRef2 = OutlineCoord(bitPattern: ref2Original)
      oldRange = state.gs.dualProjectionVector.dot(unscaledRef2 &- unscaledRef1)
      dualRefPoint = unscaledRef1
    }
    try state.withZP2 { zp2, state throws(InterpreterError) in
      try zp2.check(against: state.maxp)
      // Hoist the projection vectors out of the loop: gs's _modify accessor blocks the
      // compiler from proving movePoint doesn't change them, so they would otherwise
      // re-read each iteration.
      let projVec = state.gs.projectionVector
      let dualProjVec = state.gs.dualProjectionVector
      for _ in 0..<state.gs.loop {
        let idx = try state.stack.pop().int()
        let pt = try zp2.point(at: idx)
        var desiredProjection: F26Dot6
        if usesTwilightZone {
          desiredProjection = dualProjVec.dot(zp2.scaled(pt) &- dualRefPoint)
        } else {
          let newCoord = OutlineCoord(bitPattern: zp2.original(pt))
          desiredProjection = dualProjVec.dot(newCoord &- dualRefPoint)
        }

        if oldRange != 0 {
          // bincompat: old hinter treats F26.6 as int, casts to doubles for math
          // and converts the result back to int. emulate this casting side effect through rounding.
          desiredProjection = desiredProjection.mulDiv(currentRange, oldRange, rounding: .towardZero)
        }

        let currentProjection = projVec.dot(zp2.hinted(pt) &- ref1Hinted)
        try state.gs.movePoint(in: &zp2, point: pt, delta: desiredProjection &- currentProjection)
      }
      state.gs.loop = 1
    }
  }

  @inline(always)
  static func impl_ISECT(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    /* The reference interpreter's implementation of ISECT treated F26Dot6 bit patterns as F2Dot30.
     * Each division was ultimately balanced out by a multiplication, but it resulted in odd rounding
     * behaviours that can't be replicated without taking the same approach.
     */

    // get a0 and a1 from zp0, and b0 and b1 from zp1
    let a0Idx = try state.stack.pop().int()
    let a1Idx = try state.stack.pop().int()
    let b0Idx = try state.stack.pop().int()
    let b1Idx = try state.stack.pop().int()
    let (a0, a1) = try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
      try (zone.hinted(at: a0Idx), zone.hinted(at: a1Idx))
    }
    let (b0, b1) = try state.borrowZone(type: state.gs.zp1) { zone throws(InterpreterError) in
      try (zone.hinted(at: b0Idx), zone.hinted(at: b1Idx))
    }

    try state.withZP2 { zone, state throws(InterpreterError) in
      let idx = try state.stack.pop().int()
      let pt = try zone.point(at: idx)

      // unconditionally set both xMoved and yMoved like the C++ interpreter
      // does, then never bother to set xMoved/yMoved when storing the new position
      zone.markMoved(pt, x: true, y: true)

      /*
       * (1) Bx + dBx * t0 = Ax + dAx * t1
       * (2) By + dBy * t0 = Ay + dAy * t1
       *
       *  1  =>  (t1 = Bx - Ax + dBx * t0 ) / dAx
       *  +2 =>   By + dBy * t0 = Ay + dAy/dAx * [ Bx - Ax + dBx * t0 ]
       *     => t0 * [dAy/dAx * dBx - dBy = By - Ay - dAy/dAx*(Bx-Ax)
       *     => t0(dAy*DBx - dBy*dAx) = dAx(By - Ay) + dAy(Ax-Bx)
       *     => t0 = [dAx(By-Ay) + dAy(Ax-Bx)] / [dAy*dBx - dBy*dAx]
       *     => t0 = [dAx(By-Ay) - dAy(Bx-Ax)] / [dBx*dAy - dBy*dAx]
       *     t0 = N/D
       *     =>
       *	    N = (By - Ay) * dAx - (Bx - Ax) * dAy;
       *		D = dBx * dAy - dBy * dAx;
       */
      // Where, Ax is a1.x, and dAx is a0.x - a1.x, and so on.
      // The old code didn't calculate N and D directly, instead it
      // calculated them already divided by the larger of dAy & dAx, quote:
      /* To prevent out of range problems divide both N and D with the max */

      let dAx = a0.x &- a1.x
      let dAy = a0.y &- a1.y
      let dBx = b0.x &- b1.x
      let dBy = b0.y &- b1.y

      let n: F26Dot6
      let d: F26Dot6
      if dAy == 0 {
        if dBx == 0 {
          zone.setHinted(pt, OutlineCoord(x: b1.x, y: a1.y))
          return
        }
        n = b1.y &- a1.y
        d = 0 &- dBy
      } else if dAx == 0 {
        if dBy == 0 {
          zone.setHinted(pt, OutlineCoord(x: a1.x, y: b1.y))
          return
        }
        n = b1.x &- a1.x
        d = 0 &- dBx
      } else if dAx.magnitude > dAy.magnitude {
        /* To prevent out of range problems divide both N and D with the max */
        let t = fractDivide(dAy, dAx)
        n = (b1.y &- a1.y) &- fractMultiply(t, (b1.x &- a1.x))
        d = fractMultiply(dBx, t) &- dBy
      } else {
        let t = fractDivide(dAx, dAy)
        n = fractMultiply((b1.y &- a1.y), t) &- (b1.x &- a1.x)
        d = dBx &- fractMultiply(dBy, t)
      }

      // This part wasn't elucidated in the original code or comments
      if d != 0 {
        if n.magnitude < d.magnitude {
          /* "this is the normal case" */
          let t = fractDivide(n, d)
          zone.setHinted(pt, OutlineCoord(x: b1.x &+ fractMultiply(dBx, t), y: b1.y &+ fractMultiply(dBy, t)))
        } else {
          /* "Oh well, invert t and use it instead" */
          let t = fractDivide(d, n)
          zone.setHinted(pt, OutlineCoord(x: b1.x &+ fractDivide(dBx, t), y: b1.y &+ fractDivide(dBy, t)))
        }
      } else {
        // Degenerate case: parallel lines. Just find the midpoint of all 4 points.
        zone.setHinted(pt, OutlineCoord(
          x: (b1.x &+ (dBx / 2) &+ a1.x &+ (dAx / 2)) / 2,
          y: (b1.y &+ (dBy / 2) &+ a1.y &+ (dAy / 2)) / 2
        ))
      }
    }
  }

  @inline(always)
  static func impl_IUPX(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.withZP2 { zone, state throws(InterpreterError) in
      try zone.iup(&state, axis: .x)
    }
  }

  @inline(always)
  static func impl_IUPY(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.withZP2 { zone, state throws(InterpreterError) in
      try zone.iup(&state, axis: .y)
    }
  }

  @inline(always)
  static func impl_JMPR(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let n = try state.stack.pop().int32()
    try state.executionState.topFrame.jump(n)
  }

  @inline(always)
  static func impl_JROF(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let val = try state.stack.pop().int32()
    let n = try state.stack.pop().int32()
    if val == 0 {
      try state.executionState.topFrame.jump(n)
    }
  }

  @inline(always)
  static func impl_JROT(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let val = try state.stack.pop().int32()
    let n = try state.stack.pop().int32()
    if val != 0 {
      try state.executionState.topFrame.jump(n)
    }
  }

  @inline(always)
  static func impl_LOOPCALL(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let f = try state.stack.pop().int32()
    // Old interpreter quietly returned if given a function that's
    // not yet defined, or a loop count that's 0 or negative. Only
    // a function number outside the safe range causes an error.
    guard f >= 0, f < state.executionState.fdefs.capacity + kMaxFunctionDefsSafeMargin else {
      throw .maxpLimitExceeded
    }
    let count = try state.stack.pop().int()
    try state.executionState.call(type: .function(f), loop: count)
  }

  @inline(always)
  static func impl_LT(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands(<))
  }

  @inline(always)
  static func impl_LTEQ(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands(<=))
  }

  @inline(always)
  static func impl_MAX(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands(max))
  }

  @inline(always)
  static func impl_MD(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let p2index = try state.stack.pop().int()
    let p1index = try state.stack.pop().int()
    if Opcode.MD.immediate(for: instruction) == 0 {
      let p1Hinted = try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
        try zone.hinted(at: p1index)
      }
      let p2Hinted = try state.borrowZone(type: state.gs.zp1) { zone throws(InterpreterError) in
        try zone.hinted(at: p2index)
      }
      try state.stack.push(StackElement(state.gs.projectionVector.dot(p1Hinted &- p2Hinted)))
    } else {
      if state.executionState.program == .glyf, state.unscaledOutlineIsWrong {
        try state.correctUnscaledOutline()
      }
      let p1Original = try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
        try zone.original(at: p1index)
      }
      let p2Original = try state.borrowZone(type: state.gs.zp1) { zone throws(InterpreterError) in
        try zone.original(at: p2index)
      }
      // Bincompat: The reference interpreter uses unscaled points (int16) with F26.6 arithmetic.
      let distance = OutlineCoord(bitPattern: p1Original &- p2Original)
        .mixedMulRoundingToNearestOrUp(state.scaleFactors.unitsPerEmScale)
      let projected = state.gs.dualProjectionVector.dot(distance)
      try state.stack.push(StackElement(projected.bitPattern))
    }
  }

  @inline(always)
  static func impl_MDAP(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let idx = try state.stack.pop().int()
    try state.withZP0 { zp0, state throws(InterpreterError) in
      try zp0.check(against: state.maxp)
      let pt = try zp0.point(at: idx)
      state.gs.rp0 = idx
      state.gs.rp1 = idx
      let distance: F26Dot6
      if Opcode.MDAP.immediate(for: instruction) == 1 {
        let currProj = state.gs.projectionVector.dot(zp0.hinted(pt))
        let resultProj = state.gs.roundState.round(currProj)
        distance = resultProj &- currProj
      } else {
        distance = 0
      }

      // BUG: MDAP is supposed to always set the xMoved/yMoved flag on the
      // non-zero axes of the projection vector, but the C++ implementation
      // relies on MovePoint doing it. We intentionally reproduce this bug.
      try state.gs.movePoint(in: &zp0, point: pt, delta: distance)
    }
  }

  @inline(always)
  static func impl_MDRP(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let immediate = Opcode.MDRP.immediate(for: instruction)

    let usesTwilightZone = state.gs.zp0 == .twilight || state.gs.zp1 == .twilight
    if !usesTwilightZone, state.unscaledOutlineIsWrong {
      try state.correctUnscaledOutline()
    }

    let pt0Index = state.gs.rp0
    let pt1Index = try state.stack.pop().int()
    try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
      try zone.check(against: state.maxp)
    }
    let (pt0Hinted, pt0Reference): (OutlineCoord, OutlineCoord) =
      try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
        let p = try zone.point(at: pt0Index)
        // Only one of `scaled` and `original` is used inside the loop, depending on
        // `usesTwilightZone`. Compute only the relevant one — saves the unused span loads.
        let hinted = zone.hinted(p)
        let reference: OutlineCoord =
          usesTwilightZone ? zone.scaled(p) : OutlineCoord(bitPattern: zone.original(p))
        return (hinted, reference)
      }

    try state.withZP1 { zp1, state throws(InterpreterError) in
      try zp1.check(against: state.maxp)
      let pt = try zp1.point(at: pt1Index)
      var distanceToMove: F26Dot6
      if usesTwilightZone {
        distanceToMove = state.gs.dualProjectionVector.dot(zp1.scaled(pt) &- pt0Reference)
      } else {
        // Note: The reference interpreter reads unscaled points and treats them like F16.16 numbers
        // when they are in fact int16_t. This results in values that are 65536 times too small.
        // This code reproduces this behavior.
        let stretched = OutlineCoord(bitPattern: zp1.original(pt)) &- pt0Reference
        if state.scaleFactors.unitsPerEmScale.x != state.scaleFactors.unitsPerEmScale.y {
          let scaled = stretched.mixedMulRoundingToNearestOrUp(state.scaleFactors.unitsPerEmScale)
          distanceToMove = state.gs.dualProjectionVector.dot(scaled)
        } else {
          let projected = state.gs.dualProjectionVector.dot(stretched)
          distanceToMove = projected.mixedMulRoundingToNearestOrUp(state.scaleFactors.unitsPerEmScale.x)
        }
      }

      distanceToMove = state.applySingleWidthCutIn(distanceToMove)
      let distanceNegativeBeforeRounding = distanceToMove < 0
      if immediate & 0b100 == 0b100 {
        distanceToMove = state.gs.roundState.round(distanceToMove)
      }
      distanceToMove = clampToMinimumDistance(
        minimumDistance: immediate & 0b1000 == 0b1000 ? state.gs.minimumDistance : 0,
        distance: distanceToMove,
        biasNegative: distanceNegativeBeforeRounding
      )

      distanceToMove &-= state.gs.projectionVector.dot(zp1.hinted(pt) &- pt0Hinted)
      try state.gs.movePoint(in: &zp1, point: pt, delta: distanceToMove)

      state.gs.rp1 = pt0Index
      state.gs.rp2 = pt1Index
      if immediate & 0b10000 == 0b10000 {
        state.gs.rp0 = pt1Index
      }
    }
  }

  @inline(always)
  static func impl_MIAP(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let entryIndex = try state.stack.pop().int()
    let pointIndex = try state.stack.pop().int()
    let newProjection = try state.cvt.readEntry(entryIndex).stretched(by: state.effectiveCVTScale())
    try state.withZP0 { zp0, state throws(InterpreterError) in
      try zp0.check(against: state.maxp)
      let pt = try zp0.point(at: pointIndex)
      let currentProjection: F26Dot6
      if state.gs.zp0 == .twilight {
        // movePoint below applies xMoved/yMoved.
        let updated = OutlineCoord(scaling: newProjection, by: state.gs.projectionVector)
        zp0.setHinted(pt, updated)
        zp0.setScaled(pt, updated)
        currentProjection = state.gs.projectionVector.dot(updated)
      } else {
        currentProjection = state.gs.projectionVector.dot(zp0.hinted(pt))
      }

      // only set RP0, RP1 after we have been able to access the `pointIndex` point
      state.gs.rp0 = pointIndex
      state.gs.rp1 = pointIndex

      var newProjection = newProjection
      if Opcode.MIAP.immediate(for: instruction) == 1 {
        newProjection = state.roundAndCutIn(
          distanceToMove: newProjection,
          distanceBetweenPoints: currentProjection
        )
      }

      try state.gs.movePoint(in: &zp0, point: pt, delta: newProjection &- currentProjection)
    }
  }

  @inline(always)
  static func impl_MIN(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands(min))
  }

  @inline(always)
  static func impl_MINDEX(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let index = try state.stack.pop().uint32()
    do {
      try state.stack.push(state.stack.removeAt(indexBelowTop: index))
    } catch .stackUnderflow {
      // Instruction Set Reference does not say whether zero or negative is
      // an error. Cpp interpreter and FreeType both return the original stack.
      try state.stack.push(StackElement(index))
      // That said, the Cpp interpreter *does* throw on negative/high indexes
      if index != 0 { throw .stackUnderflow }
    }
  }

  @inline(always)
  static func impl_MIRP(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let immediate = Opcode.MIRP.immediate(for: instruction)

    let entryIndex = try state.stack.pop().int()
    var distanceToMove = try state.cvt.readEntry(entryIndex).stretched(by: state.effectiveCVTScale())
    let pointIndex = try state.stack.pop().int()
    let rp0 = state.gs.rp0
    let (rpScaled, rpHinted): (OutlineCoord, OutlineCoord) =
      try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
        let p = try zone.point(at: rp0)
        return (zone.scaled(p), zone.hinted(p))
      }

    distanceToMove = state.applySingleWidthCutIn(distanceToMove)
    try state.withZP1 { zp1, state throws(InterpreterError) in
      try zp1.check(against: state.maxp)
      let pt = try zp1.point(at: pointIndex)
      let distanceBetweenPoints: F26Dot6
      if state.gs.zp1 == .twilight {
        let distance: FixedVector<F26Dot6> = .init(scaling: distanceToMove, by: state.gs.projectionVector)
        zp1.setScaled(pt, rpScaled &+ distance)
        zp1.setHinted(pt, rpHinted)
        distanceBetweenPoints = distanceToMove
      } else {
        distanceBetweenPoints = state.gs.dualProjectionVector.dot(
          zp1.scaled(pt) &- rpScaled
        )
      }

      var distanceToMove = distanceToMove
      if state.gs.autoFlip, (distanceToMove < 0) != (distanceBetweenPoints < 0) {
        distanceToMove = 0 &- distanceToMove
      }

      if immediate & 0b100 == 0b100 {
        distanceToMove = state.roundAndCutIn(
          distanceToMove: distanceToMove,
          distanceBetweenPoints: distanceBetweenPoints
        )
      }

      distanceToMove = clampToMinimumDistance(
        minimumDistance: immediate & 0b1000 == 0b1000 ? state.gs.minimumDistance : 0,
        distance: distanceToMove,
        biasNegative: distanceBetweenPoints < 0
      )

      distanceToMove &-= state.gs.projectionVector.dot(zp1.hinted(pt) &- rpHinted)
      try state.gs.movePoint(in: &zp1, point: pt, delta: distanceToMove)
      state.gs.rp1 = rp0
      state.gs.rp2 = pointIndex
      if immediate & 0b10000 == 0b10000 {
        state.gs.rp0 = pointIndex
      }
    }
  }

  @inline(always)
  static func impl_MPPEM(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(StackElement(withoutExtending: state.substate.projectedIntegerPPEM))
  }

  @inline(always)
  static func impl_MPS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(StackElement(state.scaleFactors.pointSize))
  }

  @inline(always)
  static func impl_MSIRP(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let distanceValue = try state.stack.pop().f26dot6()
    let pointToModify = try state.stack.pop().int()
    let rp0 = state.gs.rp0
    let isTwilight = state.gs.zp1 == .twilight
    // We need refHinted always, and refScaled only when zp1 is twilight. Read both
    // from zp0 in one borrow and discard the unused one.
    let (refHinted, refScaled): (OutlineCoord, OutlineCoord) =
      try state.borrowZone(type: state.gs.zp0) { zone throws(InterpreterError) in
        let p = try zone.point(at: rp0)
        return (zone.hinted(p), isTwilight ? zone.scaled(p) : OutlineCoord(x: 0, y: 0))
      }
    try state.withZP1 { zp1, state throws(InterpreterError) in
      try zp1.check(against: state.maxp)
      let pt = try zp1.point(at: pointToModify)
      if isTwilight {
        let d = FixedVector<F26Dot6>(scaling: distanceValue, by: state.gs.projectionVector)
        zp1.setScaled(pt, refScaled &+ d)
        zp1.setHinted(pt, refHinted)
      }
      let distanceBetweenPoints = state.gs.projectionVector.dot(zp1.hinted(pt) &- refHinted)
      try state.gs.movePoint(in: &zp1, point: pt, delta: distanceValue &- distanceBetweenPoints)
    }
    state.gs.rp1 = rp0
    state.gs.rp2 = pointToModify
    if Opcode.MSIRP.immediate(for: instruction) == 1 {
      state.gs.rp0 = pointToModify
    }
  }

  @inline(always)
  static func impl_MUL(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(
      state.withTwoF26Operands { a, b in
        let FASTMUL26LIMIT: Int32 = 46_340
        let FASTMUL26RANGE = -FASTMUL26LIMIT...FASTMUL26LIMIT
        let roundingMode: RoundingRule =
        FASTMUL26RANGE.contains(a.bitPattern) && FASTMUL26RANGE.contains(b.bitPattern)
        ? .toNearestOrUp : .toNearestOrAway
        return a.multipliedReportingOverflow(by: b, rounding: roundingMode).wrappedValue
      }
    )
  }

  @inline(always)
  static func impl_NEG(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withOneF26Operand { $0 == .min ? .min : -$0 })
  }

  @inline(always)
  static func impl_NEQ(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands(!=))
  }

  @inline(always)
  static func impl_NOT(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let val = try state.stack.pop().int32()
    let notVal: Int32 = (val == 0) ? 1 : 0
    try state.stack.push(StackElement(notVal))
  }

  @inline(always)
  static func impl_NPUSHB(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    guard let byteCount = state.executionState.nextOpcode() else { throw .ranOffEndOfInstructions }
    try state.pushb(count: .init(byteCount))
  }

  @inline(always)
  static func impl_NPUSHW(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    guard let wordCount = state.executionState.nextOpcode() else { throw .ranOffEndOfInstructions }
    try state.pushw(count: .init(wordCount))
  }

  @inline(always)
  static func impl_NROUND(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    assert(Opcode.NROUND.range ~= instruction)
    // no-op when rounding doesn't have engine characteristics, but
    // there must be at least 1 item on the stack
    guard !state.stack.isEmpty else {
      throw .stackUnderflow
    }
  }

  @inline(always)
  static func impl_ODD(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let num = try state.stack.pop().f26dot6()
    let rounded = RoundState.rtg.round(num).integralPart
    try state.stack.push(StackElement(rounded.isMultiple(of: 2) ? 0 : 1 as Int32))
  }

  @inline(always)
  static func impl_OR(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoI32Operands { $0 != 0 || $1 != 0 })
  }

  @inline(always)
  static func impl_POP(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.pop()
  }

  @inline(always)
  static func impl_PUSHB(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    try state.pushb(count: Opcode.PUSHB.decodeCount(from: instruction))
  }

  @inline(always)
  static func impl_PUSHB0(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    guard let next = state.executionState.nextOpcode() else { throw .ranOffEndOfInstructions }
    try state.stack.push(.init(next))
  }

  @inline(always)
  static func impl_PUSHW(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    try state.pushw(count: Opcode.PUSHW.decodeCount(from: instruction))
  }

  @inline(always)
  static func impl_PUSHW0(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    guard let first = state.executionState.nextOpcode(),
          let second = state.executionState.nextOpcode()
    else { throw .ranOffEndOfInstructions }
    try state.stack.push(.init(highByte: first, lowByte: second))
  }

  @inline(always)
  static func impl_RCVT(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let index = try state.stack.pop().int()
    guard state.executionState.program != .fpgm else {
      try state.stack.push(StackElement(Int32(0)))
      return
    }
    do {
      let value = try state.cvt.readEntry(index).stretched(by: state.effectiveCVTScale())
      try state.stack.push(StackElement(value))
    } catch .cvtLocationOutOfBounds {
      // Instruction Set Reference does not actually say OOB indexing is an error!
      // Negative indexes are prohibited by Cpp, but both Cpp interpreter and FreeType
      // replace the top of the stack wit 0.
      if index < 0 { throw .cvtLocationOutOfBounds }
      try state.stack.push(StackElement(Int32(0)))
    }
  }

  @inline(always)
  static func impl_RDTG(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.roundState = .rdtg
  }

  @inline(always)
  static func impl_ROFF(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.roundState = .roff
  }

  @inline(always)
  static func impl_ROLL(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.roll()
  }

  @inline(always)
  static func impl_ROUND(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let arg = try state.stack.pop().f26dot6()
    try state.stack.push(.init(state.gs.roundState.round(arg)))
  }

  @inline(always)
  static func impl_RS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let location = try state.stack.pop().uint32()
    try state.stack.push(StackElement(state.storageArea.read(location)))
  }

  @inline(always)
  static func impl_RTDG(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.roundState = .rtdg
  }

  @inline(always)
  static func impl_RTG(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.roundState = .rtg
  }

  @inline(always)
  static func impl_RTHG(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.roundState = .rthg
  }

  @inline(always)
  static func impl_RUTG(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.roundState = .rutg
  }

  @inline(always)
  static func impl_S45ROUND(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let roundParam = try state.stack.pop().uint8()
    state.gs.roundState = .init(super45RoundParameter: roundParam)
  }

  @inline(always)
  static func impl_SANGW(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.pop()
  }

  @inline(always)
  static func impl_SCANCTRL(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let userValue = try state.stack.pop().uint32()
    // bincompat: reference interpreter does not properly mask off the stack value.
    // unclear if this is used directly in the scaler, but just in case.
    state.gs.scanControl.rawValue = (state.gs.scanControl.rawValue & ~UInt32(UInt16.max)) | userValue
  }

  @inline(always)
  static func impl_SCANTYPE(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    switch try state.stack.pop().int() {
    case 0: state.gs.scanControl.kind = .noControl
    case 1: state.gs.scanControl.kind = .stubControl
    case 2: state.gs.scanControl.kind = .noDoControl
    default: return
    }
  }

  @inline(always)
  static func impl_SCFS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let coord = try state.stack.pop().f26dot6()
    let pidx = try state.stack.pop().int()

    try state.withZP2 { zone, state throws(InterpreterError) in
      try zone.check(against: state.maxp)
      let pt = try zone.point(at: pidx)
      // gs.projectionVector.dot(p) is how much of the distance toward "coord" the point p has
      // already covered at its current position
      // subtracting that from coord is how much farther p has to be moved along proj vector
      // to reach distance "coord"
      try state.gs.movePoint(in: &zone, point: pt, delta: coord &- state.gs.projectionVector.dot(zone.hinted(pt)))

      // When in the twilight zone, the Cpp, FreeType, and MS interpreters update the unhinted coordinate.
      if state.gs.zp2 == .twilight {
        zone.setScaled(pt, zone.hinted(pt))
      }
    }
  }

  @inline(always)
  static func impl_SCVTCI(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.cvt.controlValueCutIn = try state.stack.pop().f26dot6()
  }

  @inline(always)
  static func impl_SDB(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.deltaBase = try Int16(truncatingIfNeeded: state.stack.pop().int32())
  }

  @inline(always)
  static func impl_SDPVTL(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let rotated = Opcode.SDPVTL.immediate(for: instruction) == 1
    let p2Index = try state.stack.pop().int()
    let p1Index = try state.stack.pop().int()

    let (p2Hinted, p2Scaled): (OutlineCoord, OutlineCoord) =
      try state.borrowZone(type: state.gs.zp2) { zone throws(InterpreterError) in
        try zone.check(against: state.maxp)
        let p = try zone.point(at: p2Index)
        return (zone.hinted(p), zone.scaled(p))
      }

    // Bincompat: zone1 is not checked by SDPVTL
    let (p1Hinted, p1Scaled): (OutlineCoord, OutlineCoord) =
      try state.borrowZone(type: state.gs.zp1) { zone throws(InterpreterError) in
        let p = try zone.point(at: p1Index)
        return (zone.hinted(p), zone.scaled(p))
      }

    let projVec = computeUnitVector(
      p1: p1Hinted,
      p2: p2Hinted,
      rotated: rotated
    )
    let dualProjVec = computeUnitVector(
      p1: p1Scaled,
      p2: p2Scaled,
      rotated: rotated
    )
    state.gs.projectionVector = projVec
    state.gs.dualProjectionVector = dualProjVec
    state.gs.projectionVectorIsNormal = rotated
  }

  @inline(always)
  static func impl_SDS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.deltaShift = try Int16(truncatingIfNeeded: state.stack.pop().int32())
  }

  @inline(always)
  static func impl_SFVFS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    // Unnormalized... If the vector isn't a unit vector you're just going to get wrong answers...
    let y = try state.stack.pop().f2dot14()
    let x = try state.stack.pop().f2dot14()
    state.gs.freedomVector = .init(x: x, y: y)
  }

  @inline(always)
  static func impl_SFVTCA_X(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.freedomVector = .x_axis
  }

  @inline(always)
  static func impl_SFVTCA_Y(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.freedomVector = .y_axis
  }

  @inline(always)
  static func impl_SFVTL(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let rotated = Opcode.SFVTL.immediate(for: instruction) == 1
    state.gs.freedomVector = try state.unitVectorFromLine(rotated: rotated)
  }

  @inline(always)
  static func impl_SFVTPV(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.setFreedomVectorToProjectionVector()
  }

  @inline(always)
  static func impl_SHC(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let (referencePoint, referenceZoneType) =
    (Opcode.SHC.immediate(for: instruction) == 1
     ? (state.gs.rp1, state.gs.zp0)
     : (state.gs.rp2, state.gs.zp1))
    let proj = try state.borrowZone(type: referenceZoneType) { zone throws(InterpreterError) in
      let p = try zone.point(at: referencePoint)
      return state.gs.projectionVector.dot(zone.hinted(p) &- zone.scaled(p))
    }

    let contourIndex = try state.stack.pop().int()
    try state.withZP2 { zone, state throws(InterpreterError) in
      try zone.check(against: state.maxp)
      let contour = try zone.readContour(index: contourIndex)
      guard (0..<zone.maxPointCount).contains(contour) else {
        throw .invalidOperand  // Malformed font
      }

      for index in contour {
        if index == referencePoint, zone.zoneType == referenceZoneType { continue }
        let pt = try zone.point(at: index)
        try state.gs.movePoint(in: &zone, point: pt, delta: proj, ignoringOverflow: true)
      }
    }
  }

  @inline(always)
  static func impl_SHP(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let (referencePoint, referenceZoneType) =
    (Opcode.SHP.immediate(for: instruction) == 1
     ? (state.gs.rp1, state.gs.zp0)
     : (state.gs.rp2, state.gs.zp1))
    let proj = try state.borrowZone(type: referenceZoneType) { zone throws(InterpreterError) in
      let p = try zone.point(at: referencePoint)
      return state.gs.projectionVector.dot(zone.hinted(p) &- zone.scaled(p))
    }

    try state.withZP2 { zone, state throws(InterpreterError) in
      for _ in 0..<max(0, state.gs.loop) {
        let index = try state.stack.pop().int()
        let pt = try zone.point(at: index)
        try state.gs.movePoint(in: &zone, point: pt, delta: proj, ignoringOverflow: true)
      }
      // C++ implementation updates gs.loop only when everything succeeds (though every program resets loop anyway)
      state.gs.loop = 1
    }
  }

  // Note: unlike most other functions that move points along the freedom vector,
  // SHPIX does so without any regard to the projection vector's value.
  @inline(always)
  static func impl_SHPIX(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let proj = try state.stack.pop().f26dot6()
    let delta: FixedVector<F26Dot6> = .init(scaling: proj, by: state.gs.freedomVector)
    let xMoved = state.gs.freedomVector.x != 0
    let yMoved = state.gs.freedomVector.y != 0

    try state.withZP2 { zone, state throws(InterpreterError) in
      for _ in 0..<max(0, state.gs.loop) {
        let index = try state.stack.pop().int()
        let pt = try zone.point(at: index)
        zone.setHinted(pt, zone.hinted(pt) &+ delta)
        zone.markMoved(pt, x: xMoved, y: yMoved)
      }
      state.gs.loop = 1
    }
  }

  @inline(always)
  static func impl_SHZ(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let (referencePoint, referenceZoneType) =
    (Opcode.SHZ.immediate(for: instruction) == 1
     ? (state.gs.rp1, state.gs.zp0)
     : (state.gs.rp2, state.gs.zp1))
    let delta = try state.borrowZone(type: referenceZoneType) { zone throws(InterpreterError) in
      let p = try zone.point(at: referencePoint)
      return state.gs.projectionVector.dot(zone.hinted(p) &- zone.scaled(p))
    }
    try state.withZP(type: state.popZoneType()) { zone, state throws(InterpreterError) in
      // UNDOCUMENTED: the C++ interpreter does not touch points that have an index
      // smaller than the start of the first contour.
      var startIndex = try zone.readContour(index: 0).lowerBound
      guard 0..<zone.phantomStartIndex ~= startIndex else {
        throw .invalidOperand
      }

      // BUG: in the C++ interpreter, when the reference point is in the zone being modified, and its
      // index is the same or smaller as the first point to modify, the first point is skipped. (The
      // C++ interpreter also writes one past the end of the component array in that case, but we
      // don't reproduce that bug.)
      if referencePoint <= startIndex {
        startIndex += 1
      }

      let d = state.gs.vector(for: delta)

      // BUG: the C++ interpreter incorrectly sets XMOVED and YMOVED.
      // 1- XMOVED is only set if the freedom vector is non-zero on *both* the X axis and the Y axis
      // 2- YMOVED is set if either the reference point is not in the zone being modified, or else
      //    only for points after the reference point in the zone being modified
      let flagX = state.gs.freedomVector.x != 0 && state.gs.freedomVector.y != 0
      let flagY = state.gs.freedomVector.y != 0
      for index in startIndex..<zone.phantomStartIndex {
        var flagY = flagY /* shadows using parent scope's value */
        if zone.zoneType == referenceZoneType {
          if index == referencePoint {
            continue
          }
          flagY = flagY && index > referencePoint
        }
        let pt = try zone.point(at: index)
        zone.setHinted(pt, zone.hinted(pt) &+ d)
        zone.markMoved(pt, x: flagX, y: flagY)
      }
    }
  }

  @inline(always)
  static func impl_SLOOP(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.loop = try state.stack.pop().int32()
  }

  @inline(always)
  static func impl_SMD(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.minimumDistance = try state.stack.pop().f26dot6()
  }

  @inline(always)
  static func impl_SPVFS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    // Unnormalized... If the vector isn't a unit vector you're just going to get wrong answers...
    let y = try state.stack.pop().f2dot14()
    let x = try state.stack.pop().f2dot14()
    state.gs.projectionVector = .init(x: x, y: y)
  }

  @inline(always)
  static func impl_SPVTCA_X(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.projectionVector = .x_axis
  }

  @inline(always)
  static func impl_SPVTCA_Y(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.projectionVector = .y_axis
  }

  @inline(always)
  static func impl_SPVTL(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let rotated = Opcode.SPVTL.immediate(for: instruction) == 1
    state.gs.projectionVector = try state.unitVectorFromLine(rotated: rotated)
    state.gs.projectionVectorIsNormal = rotated
  }

  @inline(always)
  static func impl_SROUND(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let roundParam = try state.stack.pop().uint8()
    state.gs.roundState = .init(superRoundParameter: roundParam)
  }

  @inline(always)
  static func impl_SRP0(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.rp0 = try state.stack.pop().int()
  }

  @inline(always)
  static func impl_SRP1(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.rp1 = try state.stack.pop().int()
  }

  @inline(always)
  static func impl_SRP2(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.rp2 = try state.stack.pop().int()
  }

  @inline(always)
  static func impl_SSW(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    // BUG: the TrueType documentation says the operand is expressed
    // in (presumably integral) FUnits, but both FreeType and the
    // C++ interpreter treat it as the fractional part of a F16.16
    // value, so we do the same thing.
    // sign-extend at 16 bits
    let swValue = F16Dot16(bitPattern: (try state.stack.pop().int32() << UInt16.bitWidth) >> UInt16.bitWidth)
    let scaledSW = swValue &* state.scaleFactors.unitsPerEmScale.x
    state.cvt.singleWidthValue = ControlValue(fUnits: .init(bitPattern: scaledSW.bitPattern))
  }

  @inline(always)
  static func impl_SSWCI(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.cvt.singleWidthCutIn = try state.stack.pop().f26dot6()
  }

  @inline(always)
  static func impl_SUB(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.push(state.withTwoF26Operands(&-))
  }

  @inline(always)
  static func impl_SVTCA_X(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.freedomVector = .x_axis
    state.gs.projectionVector = .x_axis
    state.gs.alwaysTouchAxis = .x
  }

  @inline(always)
  static func impl_SVTCA_Y(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.freedomVector = .y_axis
    state.gs.projectionVector = .y_axis
    state.gs.alwaysTouchAxis = .y
  }

  @inline(always)
  static func impl_SWAP(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    try state.stack.swap()
  }

  @inline(always)
  static func impl_SZP0(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.zp0 = try state.popZoneType()
  }

  @inline(always)
  static func impl_SZP1(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.zp1 = try state.popZoneType()
  }

  @inline(always)
  static func impl_SZP2(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.zp2 = try state.popZoneType()
  }

  @inline(always)
  static func impl_SZPS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    state.gs.zp0 = try state.popZoneType()
    state.gs.zp1 = state.gs.zp0
    state.gs.zp2 = state.gs.zp0
  }

  @inline(always)
  static func impl_UTP(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let index = try state.stack.pop().int()
    try state.withZP0 { zp0, state throws(InterpreterError) in
      try zp0.check(against: state.maxp)
      let pt = try zp0.point(at: index)
      zp0.clearMoved(pt, 
        x: state.gs.freedomVector.x != 0,
        y: state.gs.freedomVector.y != 0
      )
    }
  }

  @inline(always)
  static func impl_WCVTF(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let value = try state.stack.pop().f26dot6()
    let location = try state.stack.pop().int()
    let scaled = value.mixedMulRoundingToNearestOrUp(state.scaleFactors.unitsPerEmScale.x)
    try state.cvt.writeEntry(.init(fUnits: scaled), atIndex: location)
  }

  @inline(always)
  static func impl_WCVTP(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let value = try state.stack.pop().f26dot6()
    let location = try state.stack.pop().int()
    let doublyStretched = value.mixedMulRoundingToNearestOrUp(state.effectiveCVTScale())
    if value == 0 || doublyStretched == 0 || doublyStretched == value || state.executionState.program == .fpgm {
      try state.cvt.writeEntry(.init(fUnits: value), atIndex: location)
    } else {
      let rescaled = value.mulDiv(value, doublyStretched, rounding: .towardZero)
      try state.cvt.writeEntry(.init(fUnits: rescaled), atIndex: location)
    }
  }

  @inline(always)
  static func impl_WS(
    _ state: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    let value = try state.stack.pop().uint32()
    let location = try state.stack.pop().uint32()
    try state.storageArea.write(value, at: location)
  }

  @inline(always)
  static func impl_InstructionPatch(
    _ state: inout State,
    _ instruction: UInt8
  ) throws(InterpreterError) {
    let definition = state.executionState.definition(of: .patch(instruction))
    guard !definition.isUndefined else {
      throw .illegalInstruction
    }
    try state.executionState.call(type: .patch(instruction))
  }

  @inline(always)
  static func impl_InstructionIllegal(
    _: inout State,
    _: UInt8
  ) throws(InterpreterError) {
    throw .illegalInstruction
  }
}

// MARK: Opcode innards

/// Each DELTA variant (C1/C2/C3, P1/P2/P3) handles a 16-ppem window;
/// the phase offset selects which window (0, 16, or 32).
private let kDeltaPhaseStride = 16

/// Delta modifier nibble constants: a 4-bit field encodes a signed step
/// where values 0-7 map to -8..-1 and values 8-15 map to +1..+8.
private let kDeltaNibbleMask: Int32 = 0xf
private let kDeltaNibbleMidpoint: Int32 = 8
private let kDeltaPositiveAdjustment: Int32 = 7
private let kDeltaNegativeAdjustment: Int32 = 8

// Aliases for types used by helpers later in this file that would otherwise have to use fully qualified names

private typealias Axis = SwiftTrueTypeInterpreter.Axis
private typealias ControlValueTable = SwiftTrueTypeInterpreter.ControlValueTable
private typealias F16Dot16 = SwiftTrueTypeInterpreter.F16Dot16
private typealias F18Dot14 = SwiftTrueTypeInterpreter.F18Dot14
private typealias F2Dot30 = SwiftTrueTypeInterpreter.F2Dot30
private typealias F26Dot6 = SwiftTrueTypeInterpreter.F26Dot6
private typealias FixedCoord = SwiftTrueTypeInterpreter.FixedCoord
private typealias FixedVector = SwiftTrueTypeInterpreter.FixedVector
private typealias GraphicsState = SwiftTrueTypeInterpreter.GraphicsState
private typealias InterpreterError = SwiftTrueTypeInterpreter.InterpreterError
private typealias OutlineCoord = SwiftTrueTypeInterpreter.OutlineCoord
private typealias RoundState = GraphicsState.RoundState
private typealias StackElement = SwiftTrueTypeInterpreter.StackElement
private typealias State = SwiftTrueTypeInterpreter.State
private typealias Substate = State.Substate
private typealias Zone = SwiftTrueTypeInterpreter.Zone
private typealias ZoneType = Zone.ZoneType

@inline(always) @_transparent
private func deltaCVT(state: inout State, phase: Int) throws(InterpreterError) {
  let pairCount = try state.stack.pop().int32()
  let elementsToPop = Int(pairCount &* 2)
  guard pairCount > 0, elementsToPop > 0 else {
    return
  }

  try state.substate.delta(pairCount: pairCount, elementsToPop: elementsToPop, phase: phase) {
    _,
    cvt,
    index,
    delta throws(InterpreterError) in
    var value = try cvt.readEntry(index)
    value.fUnits = value.fUnits &+ delta
    try cvt.writeEntry(value, atIndex: index)
  }
}

@inline(always) @_transparent
private func deltaMovePoint(state: inout State, phase: Int) throws(InterpreterError) {
  let pairCount = try state.stack.pop().int32()
  let elementsToPop = Int(pairCount &* 2)
  guard pairCount > 0, elementsToPop > 0 else {
    return
  }

  // BINCOMPAT: Even when zp0 refers to an obviously invalid zone, the DELTAP opcodes
  // only fail when actually attempting to modify the zone.
  if (state.gs.zp0 == .glyph && state.executionState.program != .glyf)
      || (state.gs.zp0 == .twilight && state.executionState.program == .fpgm) {
    try state.substate.delta(pairCount: pairCount, elementsToPop: elementsToPop, phase: phase) {
      gs,
      _,
      _,
      _ throws(InterpreterError) in
      throw gs.zp0 == .twilight ? .invalidAccessToTwilightZone : .invalidAccessToGlyphZone
    }
    return
  }

  try state.withZP0 { zp0, state throws(InterpreterError) in
    try state.delta(pairCount: pairCount, elementsToPop: elementsToPop, phase: phase) {
      [maxp = state.maxp] gs, _, index, delta throws(InterpreterError) in
      try zp0.check(against: maxp)
      let pt = try zp0.point(at: index)
      try gs.movePoint(in: &zp0, point: pt, delta: delta)
    }
  }
}

@_lifetime(state: copy state)
@inline(always) @_transparent
private func fliprg(_ state: inout State, onCurve: Bool) throws(InterpreterError) {
  try state.withZP0 { zone, state throws(InterpreterError) in
    try zone.check(against: state.maxp)
    let max = try state.stack.pop().int()
    let min = try state.stack.pop().int()
    guard 0..<zone.maxPointCount ~= min, 0..<zone.maxPointCount ~= max else {
      throw .invalidOperand
    }

    if max >= min {
      for index in min...max {
        if onCurve {
          zone.onCurve[index] |= Zone.Point.ONCURVE
        } else {
          zone.onCurve[index] &= ~Zone.Point.ONCURVE
        }
      }
    }
  }
}

// MARK: Opcode innards implemented in State

extension State {
  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func pushb(count n: Int) throws(InterpreterError) {
    let opcodes = try executionState.nextOpcodes(count: n)
    try substate.stack.push(bytes: opcodes)
  }

  // ye olde 16-bitte wordes
  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func pushw(count n: Int) throws(InterpreterError) {
    let (byteCount, overflow) = n.multipliedReportingOverflow(by: 2)
    guard !overflow, byteCount >= 0 else { throw .ranOffEndOfInstructions }
    let opcodes = try executionState.nextOpcodes(count: byteCount)

    var i = 0
    while i &+ 1 < opcodes.count {
      let hi = opcodes[i]
      i &+= 1
      let lo = opcodes[i]
      try stack.push(.init(highByte: hi, lowByte: lo))
      i &+= 1
    }
  }
}

// MARK: Opcode innards implemented in Substate

extension State.Substate {
  @inline(always) @_transparent
  fileprivate mutating func delta(
    pairCount: Int32,
    elementsToPop: Int,
    phase: Int,
    moveElement: (inout GraphicsState, inout ControlValueTable, Int, F26Dot6) throws(InterpreterError) -> Void
  ) throws(InterpreterError) {
    assert(
      pairCount > 0 && elementsToPop > 0,
      "must be guaranteed by caller to maintain compatible error behaviour "
      + "(soft stack check before hard zone check in point exceptions)"
    )

    // `pairs` is an ordered list of (PPEM | modifier, point index). The
    // delta function operates on all points that have the right PPEM value,
    // so we find the first one and then loop until we find a different PPEM
    // value or run out of elements.
    try stack.pop(count: elementsToPop) { [projectedIntegerPPEM] pairs throws(InterpreterError) in
      let fakePixelsPerEM = Int(projectedIntegerPPEM) - Int(gs.deltaBase) - phase
      guard 0..<kDeltaPhaseStride ~= fakePixelsPerEM else {
        return  // not within exception range
      }

      // Unfortunately, the C++ implementation of the binary search doesn't
      // behave the same as our Collection.lowerBound when the list isn't sorted,
      // so we reproduce the C++ algorithm here.
      var rangeSize = pairs.count
      var startAt = 0

      rangeSize >>= 1
      rangeSize &= ~1
      while rangeSize > 2 {
        let ppem = pairs[startAt + rangeSize].int() >> 4
        if ppem < fakePixelsPerEM {
          startAt += rangeSize
        }
        rangeSize >>= 1
        rangeSize &= ~1
      }

      for ppemIndex in stride(from: startAt, to: pairs.count, by: 2) {
        let ppemShift = pairs[ppemIndex]
        let ppem = ppemShift.int() >> 4
        // The C++ implementation of the binary search (faithfully replicated
        // here) has a mistake that causes it to end at a distance of 0...2
        // to the desired start location, so we need to check for
        // `ppem == fakePixelsPerEm` before we decide to apply deltas.
        if ppem == fakePixelsPerEM {
          var modifier = ppemShift.int32() & kDeltaNibbleMask
          modifier -= modifier >= kDeltaNibbleMidpoint ? kDeltaPositiveAdjustment : kDeltaNegativeAdjustment
          let distance = F26Dot6(bitPattern: (modifier << F26Dot6.fractionBits) &>> gs.deltaShift)
          try moveElement(&gs, &cvt, pairs[ppemIndex &+ 1].int(), distance)
        } else if ppem > fakePixelsPerEM {
          break
        }
      }
    }
  }
}

// MARK: Opcode innards implemented in Zone

extension Int {
  /// Wrapping increment function
  @inline(always) @_transparent
  fileprivate func incremented(wrappingWithin range: ClosedRange<Int>) -> Int {
    assert(range.contains(self))
    return (self == range.upperBound) ? range.lowerBound : (self &+ 1)
  }
}

extension Zone {
  /// An iterator yielding indexes from `start` (non-inclusive) to `end` (non-inclusive), with
  /// wrapping behaviour when the end is lower than the start.
  private struct UntouchedRangeIterator {
    private let range: ClosedRange<Int>
    private var index: Int
    private let end: Int

    /// Creates an iterator, or `nil` if the iterator would be empty.
    @inline(always) @_transparent
    fileprivate init?(range: ClosedRange<Int>, start: Int, end: Int) {
      if start.incremented(wrappingWithin: range) == end { return nil }
      self.range = range
      self.index = start
      self.end = end
    }

    /// Returns the next index, or `nil` if the end has been reached.
    @inline(always) @_transparent
    fileprivate mutating func next() -> Int? {
      index = index.incremented(wrappingWithin: range)
      return (index != end) ? index : nil
    }
  }

  @inline(always) @_transparent
  fileprivate mutating func iup(_: inout Substate, axis: Axis) throws(InterpreterError) {
    let contourIndices = self.contourIndices
    let maxPointCount = self.maxPointCount
    for i in contourIndices {
      let contour = try self.readContour(index: i)
      // BINCOMPAT: `ep[ctr]` is `UInt16`, but the reference implementation for IUP
      // validates the upper bound using a local `SInt16` variable
      guard
        (0..<maxPointCount).contains(contour),
        contour.upperBound <= .init(Int16.max)
      else {
        throw .invalidOperand  // Malformed font
      }

      // Hand the spans of one axis to the per-contour interpolation. With `@inline(always)`,
      // this collapses to four span-pair loads per iteration.
      switch axis {
      case .x:
        Self.iupContour(contour, hinted: &x, scaled: ox.span, original: oox.span, flags: f.span, axis: axis)
      case .y:
        Self.iupContour(contour, hinted: &y, scaled: oy.span, original: ooy.span, flags: f.span, axis: axis)
      }
    }
  }

  @inline(always) @_transparent
  private static func iupContour(
    _ contour: ClosedRange<Int>,
    hinted: inout MutableSpan<Int32>,
    scaled: Span<Int32>,
    original: Span<Int16>,
    flags: Span<UInt8>,
    axis: Axis
  ) {
    func isMoved(_ index: Int) -> Bool {
      flags[index] & axis.rawValue != 0
    }

    guard var start = contour.first(where: { isMoved($0) }) else { return }
    let finish = start
    repeat {
      var end = start
      repeat {
        end = end.incremented(wrappingWithin: contour)
      } while !isMoved(end) && start != end
      defer { start = end }

      guard var iter = UntouchedRangeIterator(range: contour, start: start, end: end) else { continue }

      let (lowPoint, highPoint) =
      original[start] < original[end]
      ? (start, end)
      : (end, start)

      let dx = hinted[lowPoint]
      let dx1 = scaled[lowPoint]
      let dx2 = Int32(original[lowPoint])
      let high = scaled[highPoint]
      let dhigh = hinted[highPoint] &- high
      let tmp32 = hinted[highPoint] &- dx
      let tmp32B = Int32(original[highPoint]) &- dx2
      let low = dx1
      let dlow = dx &- dx1

      if tmp32B != 0 {
        if tmp32B <= Int32(Int16.max), tmp32 <= Int32(Int16.max) {
          while let index = iter.next() {
            var tmp32C = scaled[index]
            if tmp32C <= low {
              tmp32C &+= dlow
            } else if tmp32C >= high {
              tmp32C &+= dhigh
            } else {
              // The arithmetic below is intentionally performed using integer math (instead of fixed point)—
              // from a fixed-point perspective, `corr` is applied to the unshifted product of two F26Dot6 values
              // (in effect an F20Dot12) before the fractional part is corrected by division.
              tmp32C = .init(original[index]) &- dx2
              tmp32C &*= tmp32
              tmp32C &+= tmp32B >> 1
              tmp32C /= tmp32B
              tmp32C &+= dx
            }
            hinted[index] = tmp32C
          }
        } else {
          while let index = iter.next() {
            var tmp32C = scaled[index]
            if tmp32C <= low {
              tmp32C &+= dlow
            } else if tmp32C >= high {
              tmp32C &+= dhigh
            } else {
              // Bincompat: The reference interpreter reinterpreted tmp32 and tmp32B as F16Dot16
              // for the purpose of computing the ratio
              let ratio: F16Dot16 = .init(bitPattern: tmp32).dividedWithSaturation(
                by: F16Dot16(bitPattern: tmp32B),
                rounding: .towardZero
              )

              // Bincompat: The F16Dot16 arithmetic below (including reading/adjusting
              // original coordinates throws(InterpreterError) in the bottom 16 bits)
              // replicates shipped behaviour.
              let originalValue = Int32(original[index])
              let shiftedByStartPoint = originalValue &- dx2
              let appliedRatio: F16Dot16 = .init(bitPattern: shiftedByStartPoint)
                .multipliedWithSaturation(by: ratio)
              tmp32C = appliedRatio.bitPattern &+ dx
            }
            hinted[index] = tmp32C
          }
        }
      } else if dlow != 0 {
        while let index = iter.next() {
          hinted[index] &+= dlow
        }
      }
    } while start != finish
  }
}

// MARK: - Helpers

@inline(always) @_transparent
private func fractDivide(_ dividend: F26Dot6, _ divisor: F26Dot6) -> F26Dot6 {
  let fractDividend = F2Dot30(bitPattern: dividend.bitPattern)
  let fractDivisor = F2Dot30(bitPattern: divisor.bitPattern)
  let result = fractDividend.dividedWithSaturation(by: fractDivisor, rounding: .towardZero)
  return .init(bitPattern: result.bitPattern)
}

@inline(always) @_transparent
private func fractMultiply(_ a: F26Dot6, _ b: F26Dot6) -> F26Dot6 {
  let fractA = F2Dot30(bitPattern: a.bitPattern)
  let fractB = F2Dot30(bitPattern: b.bitPattern)
  let product = fractA.multipliedReportingOverflow(by: fractB, rounding: .toNearestOrUp).wrappedValue
  return .init(bitPattern: product.bitPattern)
}

@inline(always) @_transparent
private func clampToMinimumDistance(
  minimumDistance: F26Dot6,
  distance: F26Dot6,
  biasNegative: Bool
) -> F26Dot6 {
  let (clampMin, clampMax) =
  minimumDistance >= 0
  ? (0 &- minimumDistance, minimumDistance)
  : (minimumDistance, 0 &- minimumDistance)
  if clampMin...clampMax ~= distance {
    return biasNegative ? clampMin : clampMax
  }
  return distance
}

extension State {
  /**
   *	This gets called if a composite glyph's program includes the instructions IP, MDRP or MD,
   *	and the font has variation coordinates.
   *	These instructions use the unscaled points, which do not necessarily reflect the hinted outlines.
   *	This function inverts the hinted outline back into the unscaled outline. This is only done once.
   */
  @_lifetime(self: copy self)
  @inline(never)
  fileprivate mutating func correctUnscaledOutline() throws(InterpreterError) {
    assert(unscaledOutlineIsWrong)  // Checked by caller
    defer { unscaledOutlineIsWrong = false }

    try withZP(type: .glyph) { zone, state throws(InterpreterError) in
      // ignore phantom points
      for index in 0..<zone.phantomStartIndex {
        let pt = try zone.point(at: index)
        let rescaled = zone.hinted(pt).div(state.scaleFactors.unitsPerEmScale)
        zone.setOriginal(pt, .init(
          x: .init(truncatingIfNeeded: rescaled.x.bitPattern),
          y: .init(truncatingIfNeeded: rescaled.y.bitPattern)
        ))
      }
    }
  }

  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func withOneF26Operand(
    _ block: (F26Dot6) throws(InterpreterError) -> F26Dot6
  ) throws(InterpreterError) -> StackElement {
    try .init(block(stack.pop().f26dot6()))
  }

  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func withTwoF26Operands(
    _ block: (F26Dot6, F26Dot6) -> F26Dot6
  ) throws(InterpreterError) -> StackElement {
    let a = try stack.pop().f26dot6()
    let b = try stack.pop().f26dot6()
    return .init(block(b, a))
  }

  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func withTwoI32Operands(
    _ block: (_ a: Int32, _ b: Int32) throws(InterpreterError) -> Int32
  ) throws(InterpreterError) -> StackElement {
    let a = try stack.pop().int32()
    let b = try stack.pop().int32()
    return try .init(block(b, a))
  }

  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func withTwoI32Operands(
    _ block: (_ a: Int32, _ b: Int32) -> Bool
  ) throws(InterpreterError) -> StackElement {
    try withTwoI32Operands { block($0, $1) ? 1 : 0 }
  }

  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func popZoneType() throws(InterpreterError) -> ZoneType {
    let val = try stack.pop().int32()
    guard let zonePointer = ZoneType(rawValue: val, maxElements: maxp.maxElements) else {
      throw .invalidOperand
    }
    return zonePointer
  }

  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func applySingleWidthCutIn(_ value: F26Dot6) -> F26Dot6 {
    substate.applySingleWidthCutIn(value)
  }

  @_lifetime(self: copy self)
  @inline(always) @_transparent
  fileprivate mutating func unitVectorFromLine(
    rotated: Bool
  ) throws(InterpreterError) -> FixedVector<SwiftTrueTypeInterpreter.F2Dot14> {
    let p2Index = try stack.pop().int()
    let p1Index = try stack.pop().int()

    let p2Hinted = try borrowZone(type: gs.zp2) { zone throws(InterpreterError) in
      try zone.check(against: self.maxp)
      return try zone.hinted(at: p2Index)
    }
    // Bincompat: zone1 is not checked by SPVTL or SFVTL
    let p1Hinted = try borrowZone(type: gs.zp1) { zone throws(InterpreterError) in
      try zone.hinted(at: p1Index)
    }
    return computeUnitVector(p1: p1Hinted, p2: p2Hinted, rotated: rotated)
  }
}

extension GraphicsState {
  /// Moves the point referenced by `point` by `delta` (measured against the projection
  /// vector) along the freedom vector. Bounds were validated at the `Zone.point(at:)` factory.
  @inline(always) @_transparent
  fileprivate mutating func movePoint(
    in zone: inout Zone,
    point: Zone.Point,
    delta: F26Dot6,
    ignoringOverflow: Bool = false
  ) throws(InterpreterError) {
    // BUG: the C++ interpreter has a bug where it sets xMoved/yMoved
    // unconditionally in the direction of the projection vector after
    // using SVTCA[0] or SVTCA[1]. This is because in that special case, it
    // sets the MovePoint function to fnt_[XY]MovePoint directly, which updates
    // [xy]Moved unconditionally, whereas fnt_MovePoint first checks that the
    // freedom vector in the desired direction is non-zero.
    var moveX = self.freedomVector.x != 0
    var moveY = self.freedomVector.y != 0
    switch self.alwaysTouchAxis {
    case .x: moveX = true
    case .y: moveY = true
    case nil: break
    }

    let projectedDelta = self.vector(for: delta)
    let current = zone.hinted(point)
    let newPosition: OutlineCoord
    if ignoringOverflow {
      newPosition = current &+ projectedDelta
    } else {
      let (sum, overflow) = current.addingReportingOverflow(projectedDelta)
      guard !overflow else {
        throw .arithmeticError
      }
      newPosition = sum
    }
    zone.setHinted(point, newPosition)
    zone.markMoved(point, x: moveX, y: moveY)
  }
}

@inline(always) @_transparent
private func computeUnitVector(
  p1: OutlineCoord,
  p2: OutlineCoord,
  rotated: Bool
) -> FixedVector<SwiftTrueTypeInterpreter.F2Dot14> {
  computeUnitVector(distance: p1 &- p2, rotated: rotated)
}

@inline(always) @_transparent
private func computeUnitVector(
  distance: FixedCoord<F26Dot6>,
  rotated: Bool
) -> FixedVector<SwiftTrueTypeInterpreter.F2Dot14> {
  // subtract as F26Dot6, normalize-and-truncate to F2Dot14 using the
  // C interpreter's algorithm, then rotate if needed
  let normalized = FixedVector<F26Dot6>(convertingIfNeeded: distance).normalizeLikeFnt_NormalizeUsedTo()
  return rotated ? .init(x: 0 &- normalized.y, y: normalized.x) : normalized
}

extension Substate {
  @inline(always) @_transparent
  fileprivate mutating func effectiveCVTScale() -> F16Dot16 {
    gs.effectiveScale(for: scaleFactors.cvtStretch)
  }

  @inline(always) @_transparent
  fileprivate mutating func applySingleWidthCutIn(_ value: F26Dot6) -> F26Dot6 {
    value < 0
    ? 0 &- posAtLeastSingleWidth(0 &- value)
    : posAtLeastSingleWidth(value)
  }

  @inline(always) @_transparent
  fileprivate mutating func posAtLeastSingleWidth(_ value: F26Dot6) -> F26Dot6 {
    guard cvt.singleWidthCutIn != 0 else {
      return value
    }

    let singleWidth = cvt.singleWidthValue.stretched(by: effectiveCVTScale())
    var delta = value &- singleWidth
    if delta < 0 {
      delta = 0 &- delta
    }
    return delta < cvt.singleWidthCutIn ? singleWidth : value
  }

  @inline(always) @_transparent
  fileprivate func roundAndCutIn(
    distanceToMove: F26Dot6,
    distanceBetweenPoints: F26Dot6
  ) -> F26Dot6 {
    var distanceToMove = distanceToMove
    var cut = distanceToMove &- distanceBetweenPoints
    if cut < 0 {
      cut = 0 &- cut
    }
    if cut > cvt.controlValueCutIn {
      distanceToMove = distanceBetweenPoints
    }
    return gs.roundState.round(distanceToMove)
  }

  @inline(always) @_transparent
  fileprivate var projectedIntegerPPEM: Int16 {
    // Imperative form to avoid copies of large values; the optimizer doesn't yet handle them ergonomically.
    mutating get {
      let stretch = scaleFactors.integerPointsPerEm
      if stretch.x == stretch.y {
        return stretch.x
      }
      if gs.projectionVector.y == 0 {
        return stretch.x
      }
      if gs.projectionVector.x == 0 {
        return stretch.y
      }
      // this uses Double math in the C++ interpreter
      let h = hypot(
        Double(stretch.x) * Double(gs.projectionVector.x),
        Double(stretch.y) * Double(gs.projectionVector.y)
      )
      let fh = F18Dot14(clamping: h).roundingWithSaturation()
      return .init(truncatingIfNeeded: fh.integralPart)
    }
  }
}
