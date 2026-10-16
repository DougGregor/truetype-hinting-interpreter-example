import SwiftTrueTypeInterpreter
import Testing

final class HintingTestInterface {
  private var interpreter: SwiftTrueTypeInterpreter
  private var maxp: sfntMaxProfileTable
  private var fpgm: ContiguousArray<UInt8> = .init()
  private var prep: ContiguousArray<UInt8> = .init()

  private lazy var glyphZone: TestZone = .init(type: .glyph, maxp: maxp)
  private lazy var twilightZone: TestZone = .init(type: .twilight, maxp: maxp)

  var didFail: Bool = false

  func engineStateVariables() -> EngineStateVariables {
    let state = interpreter.graphicsState
    return EngineStateVariables(
      autoFlip: state.autoFlip,
      controlValueCutIn: interpreter.controlValueCutIn,
      deltaBase: state.deltaBase,
      deltaShift: state.deltaShift,
      dualProjectionVector: state._dualProjectionVector,
      freedomVector: state.freedomVector,
      loop: state.loop,
      minimumDistance: state.minimumDistance,
      projectionVector: state.projectionVector,
      roundState: state.roundState,
      rp0: state.rp0,
      rp1: state.rp1,
      rp2: state.rp2,
      instructControl: state.instructControl,
      scanControl: state.scanControl,
      singleWidthCutIn: interpreter.singleWidthCutIn,
      singleWidthValue: interpreter.singleWidthValue,
      zp0: state.zp0,
      zp1: state.zp1,
      zp2: state.zp2
    )
  }

  func engineState() -> EngineState {
    EngineState(
      variables: self.engineStateVariables(),
      twilightPoints: EngineStatePointZone(zoneType: .twilight, points: twilightZone.points),
      glyphPoints: EngineStatePointZone(zoneType: .glyph, points: glyphZone.points),
      stack: self.stackView(),
      storage: self.storageView(),
      cvt: self.cvtView()
    )
  }

  init(maxp: sfntMaxProfileTable, cvtCount: UInt16) {
    self.maxp = maxp
    self.interpreter = SwiftTrueTypeInterpreter(maxp: maxp, cvtCount: cvtCount)
  }

  func run(
    _ program: HintingProgram,
    instructions: [HintingInstruction],
    unscaledOutlineIsWrong: Bool,
    failure: InterpreterError?,
    sourceLocation: SourceLocation
  ) {
    self.didFail = true

    do {
      let instructionStream: ContiguousArray<UInt8> = .init(instructions.flatMap(\.stream))
      var glyf: ContiguousArray<UInt8> = .init()

      switch program {
      case .fpgm:
        fpgm = instructionStream
      case .prep:
        prep = instructionStream
      case .glyf:
        glyf = instructionStream
      }

      // Opcode tests don't use the parameter block but actual programs always do.
      // Parameter kept as non-optional to minimize dead code paths in production.
      var parBlock: fnt_ParameterBlock = .init()

      // Locals, so that spans over the programs are bounded by this scope.
      let fpgm = self.fpgm
      let prep = self.prep

      switch program {
      case .fpgm:
        try interpreter.runProgram(
          fpgm: fpgm.span, prep: prep.span, glyf: glyf.span,
          unscaledOutlineIsWrong: unscaledOutlineIsWrong,
          parBlock: &parBlock
        )
      case .prep:
        try interpreter.runProgram(
          fpgm: fpgm.span, prep: prep.span, glyf: glyf.span,
          twilightZone: &twilightZone.element,
          unscaledOutlineIsWrong: unscaledOutlineIsWrong,
          parBlock: &parBlock
        )
      case .glyf:
        try interpreter.runProgram(
          fpgm: fpgm.span, prep: prep.span, glyf: glyf.span,
          twilightZone: &twilightZone.element,
          glyphZone: &glyphZone.element,
          unscaledOutlineIsWrong: unscaledOutlineIsWrong,
          parBlock: &parBlock
        )
      }
    } catch {
      guard let failure else {
        Issue.record("interpreter unexpectedly errored: \(error)", sourceLocation: sourceLocation)
        return
      }

      guard let error = error as? InterpreterError else {
        Issue.record("interpreter threw non-InterpreterError: \(error)", sourceLocation: sourceLocation)
        return
      }

      if error != failure {
        Issue.record("interpreter threw \(error), expected \(failure)", sourceLocation: sourceLocation)
      }

      return
    }

    if failure != nil {
      Issue.record("interpreter unexpectedly did not error", sourceLocation: sourceLocation)
    }
  }

  func setPoints(_ points: [OutlinePoint], forZone zoneType: ZoneType) {
    switch zoneType {
    case .glyph:
      glyphZone.outlinePoints = points
    case .twilight:
      twilightZone.outlinePoints = points
    }
  }

  func setContours(_ contours: [Range<Int>], forZone zoneType: ZoneType) {
    switch zoneType {
    case .glyph:
      glyphZone.contours = contours.map { .init($0) }
    case .twilight:
      twilightZone.contours = contours.map { .init($0) }
    }
  }

  private func stackView() -> [Int32] {
    interpreter.stackView()
  }

  private func storageView() -> [Int32] {
    interpreter.storageView()
  }

  func setStorageValue(_ value: Int32, at idx: UInt, sourceLocation _: SourceLocation = #_sourceLocation) {
    try! interpreter.writeStorageArea(UInt32(bitPattern: value), at: UInt32(idx))
  }

  private func cvtView() -> [F26Dot6] {
    interpreter.cvtView()
  }

  func setCVT(_ values: [F26Dot6]) {
    interpreter.setCVTValues(values)
  }

  func setVariationCoord(_ coord: [CShort]) {
    interpreter.setVariationCoord(coord.span)
  }

  func setNullVariationCoord(count: Int) {
    interpreter.setNullVariationCoord(count: count)
  }

  func setScaleFactors(
    xStretch: F16Dot16,
    yStretch: F16Dot16,
    unitsPerEm: Int16,
    pointSize: Int32,
    cvtScale: F16Dot16,
    isRotated: Bool,
    isStretched: Bool
  ) {
    interpreter.setScaleFactors(
      xStretch: xStretch.bitPattern,
      yStretch: yStretch.bitPattern,
      unitsPerEm: unitsPerEm,
      pointSize: pointSize,
      cvtScale: cvtScale.bitPattern,
      isRotated: isRotated,
      isStretched: isStretched
    )
  }

  func effectiveCVTScale() -> F16Dot16 {
    var gs = interpreter._gs
    return gs.effectiveScale(for: interpreter._scaleFactors.cvtStretch)
  }
}
