// Comprehensive opcode-level tests for the TrueType hinting interpreter.

import SwiftTrueTypeInterpreter
import Testing

nonisolated(unsafe) private let kArbitraryNonzeroVector = FixedVector<F2Dot14>.normalizing(
  x: -0.707106781187,
  y: -0.707106781187
)

// Note: without at least one explicit parameter Swift will silently choose the zeroing init()
// instead of the one with default parameters.
nonisolated(unsafe) private let kDefaultMaxp: sfntMaxProfileTable = .init(version: F16Dot16(1.0).bitPattern)
private let kDefaultCVTCount: UInt16 = 32

// Validation exceptions for interpreter state that is reset and/or rolled back between programs/after errors.
private let kErrorExceptions: StateComponentOptions = [
  .stack, .referencePoints, .zonePointers, .freedomVector, .projectionVector, .loop, .glyphPoints,
]

@Suite struct HintingTests {
  // OutlinePoint and its contents print a description of themselves that is valid Swift code,
  // to aid in writing new tests
  @Test func testOutlinePointDebugDescription() {
    #expect(
      OutlinePoint(scaled: .zero, onCurve: true).debugDescription == "OutlinePoint(scaled: .zero, onCurve: true)"
    )
    #expect(
      OutlinePoint(scaled: .init(x: 1.0, y: 2.0), hinted: .zero, xMoved: true).debugDescription
      == "OutlinePoint(scaled: .init(x: 1.0, y: 2.0), hinted: .zero, xMoved: true)"
    )
    #expect(
      OutlinePoint(
        original: .init(x: 5, y: 6),
        scaled: .init(x: 1.0, y: 2.0),
        hinted: .init(x: 3.0, y: 4.0),
        yMoved: true
      ).debugDescription
      == "OutlinePoint(original: .init(x: 5, y: 6), scaled: .init(x: 1.0, y: 2.0), "
      + "hinted: .init(x: 3.0, y: 4.0), yMoved: true)"
    )
  }

  @Test func testScanControlGetters() {
    var scanControl: SwiftTrueTypeInterpreter.GraphicsState.ScanControl = .init(rawValue: 0xabcd_9876)
    #expect(0xabcd == scanControl.highBits)
    #expect(0x9876 == scanControl.lowBits)
    scanControl.highBits = 1
    scanControl.lowBits = 0x5678
    #expect(0x0001_5678 == scanControl.rawValue)
    #expect(.stubControl == scanControl.kind)
    scanControl.kind = .noDoControl
    #expect(.noControl != scanControl.kind)
  }

  // SAFETY: kDefaultMaxp is a module-level constant; nonisolated(unsafe) is only needed for global let in concurrency.
  func getInstance(
    maxp: sfntMaxProfileTable = unsafe kDefaultMaxp,
    cvtCount: UInt16 = kDefaultCVTCount
  ) -> HintingTester {
    HintingTester(interface: HintingTestInterface(maxp: maxp, cvtCount: cvtCount))
  }

  // MARK: - Instruction Helpers

  func pushF214(_ double: Double) -> HintingInstruction {
    let f214 = F2Dot14(double, rounding: .towardZero)
    return .NPUSHW([f214.bitPattern])
  }

  private func runNegativeTest(
    _ program: HintingProgram = .dontCare(),
    fUnitControlValues: [F26Dot6]? = nil,
    instructions: HintingInstruction...,
    expectingProperties properties: [EngineStateProperty] = [],
    exemptingProperties except: StateComponentOptions = [],
    failure: InterpreterError,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    runNegativeTest(
      program,
      fUnitControlValues: fUnitControlValues,
      instructions: instructions,
      expectingProperties: properties,
      exemptingProperties: except,
      failure: failure,
      sourceLocation: sourceLocation
    )
  }

  private func runNegativeTest(
    _ program: HintingProgram = .dontCare(),
    twilightPoints: [OutlinePoint]? = nil,
    glyphPoints: [OutlinePoint]? = nil,
    fUnitControlValues: [F26Dot6]? = nil,
    instructions: [HintingInstruction],
    expectingProperties properties: [EngineStateProperty] = [],
    exemptingProperties except: StateComponentOptions = [],
    failure: InterpreterError,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    var instance = getInstance(
      maxp: .init(maxPoints: 2, maxTwilightPoints: 2),
      cvtCount: UInt16(fUnitControlValues?.count ?? 0)
    )
    if let twilightPoints {
      instance.setPoints(twilightPoints, forZone: .twilight)
    }
    if let glyphPoints {
      instance.setPoints(glyphPoints, forZone: .glyph)
    }
    if let fUnitControlValues {
      instance.setCVT(fUnitControlValues)
    }
    instance.run(program, instructions: instructions, failure: failure, sourceLocation: sourceLocation)
    for property in properties {
      instance.expectedEngineState.assign(property: property)
    }

    instance.validate(except: except.union(kErrorExceptions), sourceLocation: sourceLocation)
  }

  private func runStackUnderflowTests(
    _ program: HintingProgram = .dontCare(),
    opcode: HintingInstruction,
    parameters: Int,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    for numParams in 0..<parameters {
      let params = Array(repeating: Int32(0), count: numParams)
      runNegativeTest(
        program,
        fUnitControlValues: [0],
        instructions: params.map { .PUSHB([UInt8($0)]) } + [opcode],
        failure: .stackUnderflow,
        sourceLocation: sourceLocation
      )
    }
  }

  private func runOneRoundingTest(
    roundingMode: RoundState,
    roundInstruction: HintingInstruction,
    value: F26Dot6,
    expectedValue: F26Dot6,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    var instance = getInstance()
    instance.run(
      instructions: [
        .setRoundState(roundingMode),
        .pushF26Dot6(value),
        roundInstruction,
      ],
      sourceLocation: sourceLocation
    )

    instance.expectedEngineState.variables.roundState = roundingMode
    instance.expectedEngineState.stack = [expectedValue.bitPattern]
    instance.validate(sourceLocation: sourceLocation)
  }

  private func runRoundingTest(
    roundingMode: RoundState,
    roundInstructions: [HintingInstruction] = [.ROUND_0, .ROUND_1, .ROUND_2, .ROUND_3],
    testNumbers: [F26Dot6] = Self.suggestedRoundingSensitiveNumbers(),
    expectedValue: (F26Dot6) -> F26Dot6,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    runRoundingTest(
      roundingMode: roundingMode,
      roundInstructions: roundInstructions,
      testNumbers: testNumbers,
      sourceLocation: sourceLocation
    ) { _, value in
      expectedValue(value)
    }
  }

  private func runRoundingTest(
    roundingMode: RoundState,
    roundInstructions: [HintingInstruction] = [.ROUND_0, .ROUND_1, .ROUND_2, .ROUND_3],
    testNumbers: [F26Dot6] = Self.suggestedRoundingSensitiveNumbers(),
    sourceLocation: SourceLocation = #_sourceLocation,
    expectedValue: (Int, F26Dot6) -> F26Dot6
  ) {
    for (index, number) in Self.extend(roundingSensitiveNumbers: testNumbers).enumerated() {
      for roundInstruction in roundInstructions {
        runOneRoundingTest(
          roundingMode: roundingMode,
          roundInstruction: roundInstruction,
          value: number,
          expectedValue: expectedValue(index, number),
          sourceLocation: sourceLocation
        )
      }
    }
  }

  private static func suggestedRoundingSensitiveNumbers() -> [F26Dot6] {
    // sensitive numbers:
    // * 0
    // * a few increments of 0.5
    // * numbers surrounding 2**25 / 2√2, 2**25 / √2 (for overflow conditions when using S45ROUND)
    // * .max
    // and their negative equivalents
    [
      .min,
      -23_726_566.40625,
      -11_863_283.203125,
      -1.5, -1, -0.5,
      0,
      +0.5, +1, +1.5,
      +11_863_283.203125,
      +23_726_566.40625,
      .max,
    ]
  }

  private static func extend(roundingSensitiveNumbers: [F26Dot6]) -> [F26Dot6] {
    let ulp = F26Dot6(bitPattern: 1)
    return roundingSensitiveNumbers.flatMap { value in
      var result: [F26Dot6] = []
      if case (let before, false) = value.subtractingReportingOverflow(ulp) {
        result.append(before)
      }
      result.append(value)
      if case (let after, false) = value.addingReportingOverflow(ulp) {
        result.append(after)
      }
      return result
    }
  }

  // MARK: - Meta Testing

  @Test func testEngineStateDefaults() {
    var instance = getInstance()

    let state = instance.engineState()

    #expect(state.stack.isEmpty)
    #expect(state.storage.count == 1_024)

    #expect(state.variables.autoFlip == true)
    #expect(state.variables.controlValueCutIn == .init(bitPattern: 0x44))  // default is "17/16 pixels"
    #expect(state.variables.deltaBase == 9)
    #expect(state.variables.deltaShift == 3)
    #expect(state.variables.dualProjectionVector == nil)
    #expect(state.variables.freedomVector == .x_axis)
    #expect(state.variables.instructControl.isEmpty)
    #expect(state.variables.loop == 1)
    #expect(state.variables.minimumDistance == 1)
    #expect(state.variables.projectionVector == .x_axis)
    #expect(state.variables.roundState == .rtg)
    #expect(state.variables.rp0 == 0)
    #expect(state.variables.rp1 == 0)
    #expect(state.variables.rp2 == 0)
    #expect(state.variables.scanControl == .init())
    #expect(state.variables.singleWidthCutIn == 0)
    #expect(state.variables.singleWidthValue == 0)
    #expect(state.variables.zp0 == .glyph)
    #expect(state.variables.zp1 == .glyph)
    #expect(state.variables.zp2 == .glyph)

    instance.validate()
  }

  @Test func testPushF26Dot6() {
    var instance = getInstance()
    let testValues: [F26Dot6] =
    [
      8.0,
      .max,
      .min,
      1.015625,
      -1.015625,
    ]
    + Array(
      repeating: .init(Double.random(in: Double(F26Dot6.min)...Double(F26Dot6.max))),
      count: 50
    )
    instance.run(instructions: testValues.map { HintingInstruction.pushF26Dot6($0) })

    instance.expectedEngineState.stack = testValues.map(\.bitPattern).reversed()
    instance.validate()
  }

  @Test func testStackDoesNotPersist() {
    var instance = getInstance()
    instance.run(.fpgm, instructions: .PUSHB([57]))

    instance.expectedEngineState = nil
    instance.run(.prep, instructions: .PUSHB([4]))
    instance.expectedEngineState.stack = [4]
    instance.validate()

    instance.run(.glyf, instructions: .PUSHB([99]))

    instance.expectedEngineState.stack = [99]
    instance.validate()
  }

  @Test func testEffectiveCVTScale() {
    func cvtScaleTest(
      cvtStretch: (x: Int32, y: Int32),
      proj: (x: Int16, y: Int16),
      expect: Int32,
      sourceLocation: SourceLocation = #_sourceLocation
    ) {
      let projVector = FixedVector<F2Dot14>(bitPatternX: proj.x, y: proj.y)
      var instance = getInstance()
      instance.setScaleFactors(
        xStretch: .init(bitPattern: cvtStretch.x),
        yStretch: .init(bitPattern: cvtStretch.y),
        cvtScale: .init(bitPattern: max(cvtStretch.x, cvtStretch.y))
      )
      instance.run(.prep, instructions: .setPV(projVector))

      #expect(instance.effectiveCVTScale().bitPattern == expect, sourceLocation: sourceLocation)

      instance.expectedEngineState.variables.projectionVector = projVector
      instance.validate()
    }

    cvtScaleTest(cvtStretch: (x: 2_097_151, y: 2_097_150), proj: (x: 0, y: 16_384), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 26_209, y: 65_536), proj: (x: -15_774, y: -4_429), expect: 27_052)
    cvtScaleTest(cvtStretch: (x: 26_209, y: 65_536), proj: (x: 15_726, y: -4_597), expect: 27_121)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -11_315, y: -11_850), expect: 35_010)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -12_527, y: 10_560), expect: 32_488)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -12_535, y: 10_551), expect: 32_472)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -12_740, y: 10_302), expect: 32_076)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -12_752, y: 10_287), expect: 32_053)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -12_829, y: 10_191), expect: 31_906)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -13_222, y: 9_675), expect: 31_175)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -14_823, y: -6_979), expect: 28_474)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -14_855, y: -6_911), expect: 28_424)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -14_856, y: -6_909), expect: 28_422)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -14_874, y: -6_870), expect: 28_395)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -14_880, y: -6_858), expect: 28_385)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -14_923, y: -6_764), expect: 28_318)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -15_383, y: 5_640), expect: 27_624)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -15_703, y: 4_673), expect: 27_159)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -15_774, y: -4_429), expect: 27_057)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -15_825, y: -4_242), expect: 26_985)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_043, y: -3_326), expect: 26_679)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_048, y: -3_303), expect: 26_672)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_143, y: -2_800), expect: 26_541)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_174, y: -2_616), expect: 26_499)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_183, y: -2_558), expect: 26_486)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_184, y: 2_549), expect: 26_485)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_186, y: -2_539), expect: 26_482)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_187, y: 2_535), expect: 26_481)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_197, y: 2_467), expect: 26_467)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_216, y: -2_338), expect: 26_441)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_217, y: 2_335), expect: 26_440)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_225, y: 2_274), expect: 26_429)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_248, y: 2_109), expect: 26_398)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_259, y: -2_019), expect: 26_383)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_263, y: 1_987), expect: 26_377)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_276, y: -1_878), expect: 26_360)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_280, y: 1_839), expect: 26_354)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_300, y: -1_659), expect: 26_327)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_312, y: -1_539), expect: 26_311)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_320, y: 1_447), expect: 26_300)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_320, y: 1_449), expect: 26_300)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_322, y: 1_429), expect: 26_297)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_326, y: -1_382), expect: 26_292)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_326, y: 1_376), expect: 26_292)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_328, y: 1_350), expect: 26_289)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_332, y: 1_299), expect: 26_284)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_342, y: 1_166), expect: 26_270)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_346, y: 1_111), expect: 26_265)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_346, y: 1_117), expect: 26_265)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_354, y: 994), expect: 26_254)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_355, y: 975), expect: 26_253)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_358, y: 922), expect: 26_249)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_359, y: -906), expect: 26_247)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_359, y: -909), expect: 26_247)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_361, y: -864), expect: 26_245)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_361, y: -867), expect: 26_245)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_362, y: -845), expect: 26_244)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_362, y: -849), expect: 26_243)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_363, y: 834), expect: 26_242)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_365, y: -789), expect: 26_239)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_365, y: -793), expect: 26_239)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_367, y: 747), expect: 26_237)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_368, y: -726), expect: 26_235)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_369, y: -697), expect: 26_234)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_370, y: 667), expect: 26_233)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_371, y: -658), expect: 26_231)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_371, y: -662), expect: 26_231)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_373, y: -590), expect: 26_229)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_373, y: -595), expect: 26_229)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_373, y: -600), expect: 26_228)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_376, y: -500), expect: 26_225)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_376, y: -511), expect: 26_224)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_376, y: -524), expect: 26_224)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_376, y: -525), expect: 26_224)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_379, y: -414), expect: 26_220)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_380, y: -362), expect: 26_219)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: -16_383, y: -185), expect: 26_215)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 11_288, y: -11_875), expect: 35_070)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 14_325, y: -7_953), expect: 29_269)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 14_646, y: -7_344), expect: 28_752)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 14_941, y: -6_723), expect: 28_291)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 14_954, y: -6_693), expect: 28_271)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_235, y: -6_027), expect: 27_844)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_726, y: -4_597), expect: 27_126)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_806, y: -4_314), expect: 27_012)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_807, y: -4_311), expect: 27_010)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_817, y: -4_275), expect: 26_996)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_821, y: -4_259), expect: 26_991)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_822, y: -4_254), expect: 26_989)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_822, y: -4_256), expect: 26_989)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 15_823, y: -4_252), expect: 26_988)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_018, y: -3_443), expect: 26_714)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_028, y: -3_397), expect: 26_700)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_142, y: 2_803), expect: 26_543)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_161, y: -2_695), expect: 26_517)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_174, y: -2_616), expect: 26_499)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_191, y: -2_508), expect: 26_475)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_193, y: -2_493), expect: 26_473)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_210, y: 2_384), expect: 26_449)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_212, y: 2_367), expect: 26_447)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_223, y: 2_291), expect: 26_432)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_237, y: -2_192), expect: 26_413)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_246, y: -2_122), expect: 26_400)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_251, y: 2_081), expect: 26_394)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_266, y: -1_961), expect: 26_373)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_267, y: -1_958), expect: 26_372)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_279, y: -1_848), expect: 26_355)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_314, y: -1_510), expect: 26_308)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_315, y: -1_507), expect: 26_307)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_320, y: 1_451), expect: 26_300)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_340, y: -1_199), expect: 26_273)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_345, y: 1_125), expect: 26_266)
    cvtScaleTest(cvtStretch: (x: 26_214, y: 65_536), proj: (x: 16_347, y: -1_099), expect: 26_264)
    cvtScaleTest(cvtStretch: (x: 65_523, y: 65_536), proj: (x: -13_508, y: -9_272), expect: 65_526)
    cvtScaleTest(cvtStretch: (x: 65_523, y: 65_536), proj: (x: 13_398, y: -9_430), expect: 65_527)
    cvtScaleTest(cvtStretch: (x: 65_524, y: 65_536), proj: (x: -13_508, y: -9_272), expect: 65_527)
    cvtScaleTest(cvtStretch: (x: 65_524, y: 65_536), proj: (x: 13_398, y: -9_430), expect: 65_528)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -10_583, y: -12_507), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -10_666, y: -12_437), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -10_671, y: -12_432), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -10_724, y: -12_387), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -10_745, y: -12_368), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -12_013, y: 11_141), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -13_508, y: -9_272), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -14_564, y: -7_504), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_243, y: 6_006), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_257, y: 5_970), expect: 65_539)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_309, y: 5_836), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_460, y: 5_424), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_584, y: 5_058), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_670, y: 4_785), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_768, y: 4_452), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_831, y: -4_222), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_879, y: -4_037), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_948, y: -3_756), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_994, y: 3_554), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -15_996, y: 3_542), expect: 65_539)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_005, y: 3_504), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_005, y: 3_505), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_044, y: 3_319), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_070, y: 3_190), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_130, y: 2_875), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_151, y: 2_756), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_152, y: 2_745), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_204, y: 2_420), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_224, y: 2_285), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_227, y: -2_265), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_229, y: -2_245), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_233, y: -2_220), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_233, y: 2_219), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_234, y: -2_212), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_243, y: -2_148), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_244, y: -2_136), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_252, y: 2_076), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_267, y: -1_952), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_267, y: -1_959), expect: 65_534)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_268, y: 1_948), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_285, y: -1_802), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_292, y: -1_731), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_297, y: 1_689), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_302, y: -1_637), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_302, y: -1_641), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_314, y: -1_511), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_316, y: -1_493), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_316, y: -1_496), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_318, y: -1_469), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_318, y: -1_471), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_334, y: -1_274), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_334, y: -1_285), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_336, y: -1_248), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_351, y: -1_035), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -16_359, y: -905), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -6_998, y: 14_814), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -6_999, y: 14_814), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -7_229, y: 14_703), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -7_270, y: 14_683), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -7_284, y: 14_676), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: -7_327, y: 14_654), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 13_398, y: -9_430), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 14_928, y: 6_752), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 15_380, y: 5_647), expect: 65_537)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 15_749, y: -4_516), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 15_749, y: -4_518), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 15_754, y: -4_501), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 15_755, y: -4_495), expect: 65_538)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 15_756, y: -4_494), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 15_807, y: -4_311), expect: 65_535)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_535), proj: (x: 15_808, y: -4_307), expect: 65_536)

    // When stretch x and y are both exactly equal 65536, the interpreters
    // don't apply the projection vector. Doing so could compute a scale
    // factor that's 1.0 +- a few bits, but the expected behavior is to
    // use exactly 1.0.
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: -12_013, y: 11_141), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: -13_508, y: -9_272), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: -15_207, y: -6_098), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: -15_373, y: -5_666), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: -16_377, y: -462), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 13_398, y: -9_430), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 14_928, y: 6_752), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_380, y: 5_647), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_488, y: -5_344), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_541, y: -5_188), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_749, y: -4_516), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_749, y: -4_518), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_754, y: -4_501), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_755, y: -4_495), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_756, y: -4_494), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_807, y: -4_311), expect: 65_536)
    cvtScaleTest(cvtStretch: (x: 65_536, y: 65_536), proj: (x: 15_808, y: -4_307), expect: 65_536)
  }

  @Test func testNormalize() {
    let normalize: (FixedVector<F26Dot6>) -> FixedVector<F2Dot14>
    normalize = { $0.normalizeLikeFnt_NormalizeUsedTo() }

    var testCoords: [((Int32, Int32), (Int16, Int16))] = [
      ((0, 16_384), (0, 16_384)),
      ((16_384, 0), (16_384, 0)),
      ((-16_384, 0), (-16_384, 0)),
      ((0, -16_384), (0, -16_384)),

      // randomly generated near axes
      ((107, -522_352), (3, -16_384)),
      ((54, -488_481), (2, -16_384)),
      ((771_176, -3), (16_384, 0)),
      ((-91, -1_041_587), (-1, -16_384)),
      ((20, 411_566), (1, 16_384)),
      ((-45, 767_679), (-1, 16_384)),
      ((5, -535_281), (0, -16_384)),
      ((-114, 81_588), (-23, 16_384)),
      ((947_880, 78), (16_384, 1)),
      ((81, -1_376_650), (1, -16_384)),
      ((-163_593, -35), (-16_384, -4)),
      ((1_506_865, -35), (16_384, 0)),
      ((24, 396_553), (1, 16_384)),
      ((364_648, 66), (16_384, 3)),
      ((-117, -1_106_005), (-2, -16_384)),
      ((29, 1_670_151), (0, 16_384)),
      ((-929_318, -30), (-16_384, -1)),
      ((1_791_937, 78), (16_384, 1)),
      ((-78, -598_907), (-2, -16_384)),
      ((105, 602_876), (3, 16_384)),

      // randomly generated within +-1024 units of origin (more plausible values)
      ((13_797, 44_938), (4_809, 15_662)),
      ((13_514, 62_943), (3_439, 16_019)),
      ((32_509, -38_153), (10_626, -12_471)),
      ((36_191, 29_060), (12_775, 10_258)),
      ((10_330, -57_722), (2_886, -16_128)),
      ((292, -65_232), (73, -16_384)),
      ((25_782, -33_025), (10_082, -12_915)),
      ((-47_585, 9_092), (-16_093, 3_075)),
      ((-10_144, -45_744), (-3_547, -15_995)),
      ((36_834, -39_374), (11_193, -11_965)),
      ((33_460, -29_714), (12_251, -10_879)),
      ((17_299, 18_275), (11_263, 11_899)),
      ((32_413, -45_718), (9_476, -13_366)),
      ((41_774, -41_474), (11_627, -11_543)),
      ((10_774, -51_474), (3_357, -16_036)),
      ((19_223, -17_010), (12_270, -10_857)),
      ((-46_077, 3_190), (-16_345, 1_132)),
      ((54_614, 56_932), (11_342, 11_823)),
      ((-53_570, 26_253), (-14_712, 7_210)),
      ((16_651, 27_974), (8_380, 14_079)),

      // randomly generated with +-32768 units of origin
      ((-517_998, -1_439_556), (-5_547, -15_416)),
      ((-878_621, -953_092), (-11_105, -12_046)),
      ((-627_138, 2_022_021), (-4_853, 15_649)),
      ((866_515, -560_486), (13_757, -8_898)),
      ((23_706, -397_488), (975, -16_355)),
      ((-1_943_201, 218_218), (-16_282, 1_828)),
      ((-2_836, 1_273_607), (-36, 16_384)),
      ((-986_569, 1_720_341), (-8_151, 14_213)),
      ((611_941, 1_815_759), (5_233, 15_526)),
      ((131_303, -1_893_905), (1_133, -16_345)),
      ((-48_832, -108_591), (-6_720, -14_943)),
      ((492_095, -1_675_868), (4_616, -15_720)),
      ((-1_657_195, -366_246), (-15_998, -3_536)),
      ((-1_619_828, 1_363_393), (-12_535, 10_550)),
      ((887_892, -1_464_705), (8_493, -14_011)),
      ((-1_877_017, 1_429_236), (-13_035, 9_926)),
      ((1_367_579, 1_080_132), (12_857, 10_155)),
      ((-848_877, -1_042_701), (-10_344, -12_706)),
      ((151_427, 811_110), (3_007, 16_106)),
      ((-1_388_819, 293_949), (-16_029, 3_393)),
      ((1_419_771, 1_750_159), (10_322, 12_724)),
      ((932_220, 252_789), (15_813, 4_288)),
      ((1_368_641, 1_188_439), (12_371, 10_742)),
      ((1_640_166, -202_002), (16_261, -2_003)),
      ((578_259, -805_869), (9_552, -13_312)),
      ((1_984_262, 1_616_689), (12_702, 10_349)),
      ((-2_043_027, 1_112_243), (-14_390, 7_834)),
      ((-343_545, 950_270), (-5_570, 15_408)),
      ((943_629, -954_784), (11_517, -11_653)),
      ((-617_963, 1_081_145), (-8_130, 14_224)),
      ((-2_070_300, 940_982), (-14_916, 6_779)),
      ((-1_534_582, 937_864), (-13_980, 8_544)),
      ((-1_824_535, 2_062_206), (-10_857, 12_271)),
      ((-1_373_470, -1_499_704), (-11_066, -12_083)),
      ((757_068, 1_872_214), (6_142, 15_189)),
      ((-1_017_340, 1_468_300), (-9_331, 13_467)),
      ((797_703, 1_753_463), (6_785, 14_913)),
      ((-1_723_657, 1_784_146), (-11_384, 11_783)),
      ((-895_510, -2_044_499), (-6_573, -15_008)),
      ((506_969, -456_007), (12_181, -10_957)),

      // randomly generated across Int32.min...max
      ((788_416_438, -554_272_624), (13_403, -9_423)),
      ((-280_566_452, 682_462_992), (-6_230, 15_153)),
      ((-805_120_690, -1_042_211_050), (-10_016, -12_966)),
      ((-373_388_481, -99_007_621), (-15_837, -4_199)),
      ((-993_621_332, 19_654_898), (-16_381, 324)),
      ((162_929_425, 417_447_207), (5_957, 15_263)),
      ((-582_060_065, -540_631_576), (-12_005, -11_150)),
      ((978_455_413, -72_626_286), (16_339, -1_213)),
      ((892_470_338, 282_203_489), (15_622, 4_940)),
      ((-796_961_272, -887_689_847), (-10_945, -12_192)),
      ((57_905_520, -55_242_236), (11_855, -11_309)),
      ((236_073_084, 333_711_843), (9_462, 13_376)),
      ((-999_706_710, -992_192_473), (-11_629, -11_541)),
      ((-537_595_296, 548_046_166), (-11_473, 11_696)),
      ((-694_169_431, -90_888_569), (-16_245, -2_127)),
      ((19_163_605, -880_157), (16_367, -752)),
    ]

#if false
    // randomly generated triggering Undefined Behavior in the C
    // reference implementation: it attempts to left-shift by a negative
    // offset. There are comments suggesting that the algorithm is only
    // to work on values within 32K units of origin, but there's also
    // an ifdef suggesting some real fonts (Heisei Kaku Gothic)
    // actually perform normalization operations outside that range.
    // In testing, the only values returned from normalizing when UB is
    // triggered are: (16384, 0), (0, 16384), or (27969, 27969) (which is
    // not even a unit vector!)
    let testUBCoords: [((Int32, Int32), (Int16, Int16))] = [
      ((-1_328_566_587, 2_133_878_456), (16_384, 0)),
      ((-20_946_030, -1_595_403_654), (16_384, 0)),
      ((1_422_719_640, 283_580_080), (16_384, 0)),
      ((1_855_085_916, 766_699_732), (16_384, 0)),
      ((132_476_920, -1_211_567_106), (16_384, 0)),
      ((1_652_336_526, 748_493_577), (0, 16_384)),
      ((-834_718_093, 1_260_727_909), (27_969, 27_969)),
      ((-2_019_677_620, 1_196_026_665), (0, 16_384)),
      ((-1_853_876_927, -582_372_557), (27_969, 27_969)),
      ((779_411_770, 1_117_582_649), (0, 16_384)),
      ((-1_588_137_008, -1_477_240_119), (0, 16_384)),
      ((-506_873_372, -2_072_558_921), (0, 16_384)),
      ((189_714_851, 1_100_196_867), (27_969, 27_969)),
      ((1_485_657_099, -789_617_406), (16_384, 0)),
      ((2_076_676_394, -144_489_419), (0, 16_384)),
      ((405_582_965, 1_643_406_443), (27_969, 27_969)),
      ((1_530_069_252, 1_163_143_790), (16_384, 0)),
      ((1_794_383_746, -382_797_611), (0, 16_384)),
      ((-1_939_060_654, -1_954_375_418), (16_384, 0)),
      ((-1_560_628_852, 189_314_660), (16_384, 0)),
      ((-1_836_747_400, -542_357_403), (0, 16_384)),
      ((689_912_239, -1_930_379_452), (16_384, 0)),
      ((514_611_698, 1_644_099_478), (16_384, 0)),
      ((-1_746_061_265, -1_265_242_695), (27_969, 27_969)),
      ((-5_253_615, -1_452_139_470), (16_384, 0)),
      ((-328_406_754, 1_659_384_573), (0, 16_384)),
      ((-1_314_424_793, -1_606_598_465), (27_969, 27_969)),
      ((-1_648_384_570, 1_123_312_646), (16_384, 0)),
      ((1_334_413_245, 829_627_017), (27_969, 27_969)),
      ((-1_658_291_023, 826_778_009), (27_969, 27_969)),
      ((1_675_384_037, 2_141_451_063), (27_969, 27_969)),
      ((2_020_925_731, 2_044_536_890), (16_384, 0)),
      ((-1_972_005_312, 1_253_419_951), (0, 16_384)),
      ((-175_087_157, 1_606_476_912), (16_384, 0)),
      ((-715_343_677, -1_557_269_529), (27_969, 27_969)),
      ((-784_314_896, -1_263_128_045), (0, 16_384)),
      ((-1_854_947_408, -2_088_653_028), (16_384, 0)),
      ((1_198_010_192, -344_453_777), (0, 16_384)),
      ((748_764_068, -1_535_039_343), (0, 16_384)),
      ((584_703_952, 1_515_934_888), (16_384, 0)),
      ((1_189_800_822, -657_608_097), (0, 16_384)),
      ((1_145_567_735, -1_850_245_889), (27_969, 27_969)),
      ((-278_391_069, 1_733_289_959), (27_969, 27_969)),
      ((-999_119_046, 1_491_033_218), (16_384, 0)),
      ((583_070_430, 1_514_315_591), (0, 16_384)),
      ((-1_948_821_607, -2_116_548_215), (27_969, 27_969)),
      ((1_390_367_388, -987_663_956), (16_384, 0)),
      ((544_089_341, -1_664_239_608), (16_384, 0)),
      ((-1_486_495_246, -1_254_765_447), (0, 16_384)),
      ((-462_467_968, 1_635_110_135), (0, 16_384)),
    ]
    testCoords.append(contentsOf: testUBCoords)
#endif

    let testValues: [(FixedVector<F26Dot6>, FixedVector<F2Dot14>)] = testCoords.map {
      inputCoord,
      expectedCoord in
      (
        FixedVector<F26Dot6>(bitPatternX: inputCoord.0, y: inputCoord.1),
        FixedVector<F2Dot14>(bitPatternX: expectedCoord.0, y: expectedCoord.1)
      )
    }

    for (input, expected) in testValues {
      let norm = normalize(input)

      // for test development
      if expected.x == 0, expected.y == 0 {
        // Not all inputs have expected values yet
        continue
      }
      // normal case, actually running tests
      #expect(norm == expected)
    }
  }

  // MARK: - SVTCA 0x00-0x01
  /*
   Sets both the projection vector and freedom vector to the same coordinate axis causing movement
   and measurement to be in the same direction. The setting of the Boolean variable a determines
   the choice of axis.

   SVTCA[ ] is a shortcut that replaces the SFVTCA[ ] and SPVTCA[ ] instructions. As a result,
   SVTCA[1] is equivalent to SFVTCA[1] followed by SPVTCA[1].
   */

  @Test func testSVTCA_X() {
    var instance = getInstance()
    // SAFETY: kArbitraryNonzeroVector is a module-level constant; nonisolated(unsafe) is only needed for concurrency.
    unsafe instance.run(instructions: .setPV(kArbitraryNonzeroVector), .setFV(kArbitraryNonzeroVector), .SVTCA_X)

    instance.expectedEngineState.variables.freedomVector = .init(x: 1, y: 0)
    instance.expectedEngineState.variables.projectionVector = .init(x: 1, y: 0)
    instance.validate()
  }

  @Test func testSVTCA_Y() {
    var instance = getInstance()
    // SAFETY: kArbitraryNonzeroVector is a module-level constant; nonisolated(unsafe) is only needed for concurrency.
    unsafe instance.run(instructions: .setPV(kArbitraryNonzeroVector), .setFV(kArbitraryNonzeroVector), .SVTCA_Y)

    instance.expectedEngineState.variables.freedomVector = .init(x: 0, y: 1)
    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate()
  }

  // MARK: - SPVTCA 0x02, 0x03
  /*
   Sets the projection vector to one of the coordinate axes depending on the value of the flag a.
   */

  @Test func testSPVTCA_X() {
    var instance = getInstance()
    // SAFETY: kArbitraryNonzeroVector is a module-level constant; nonisolated(unsafe) is only needed for concurrency.
    unsafe instance.run(instructions: .setPV(kArbitraryNonzeroVector), .SPVTCA_X)

    instance.expectedEngineState.variables.projectionVector = .init(x: 1, y: 0)
    instance.validate()
  }

  @Test func testSPVTCA_Y() {
    var instance = getInstance()
    // SAFETY: kArbitraryNonzeroVector is a module-level constant; nonisolated(unsafe) is only needed for concurrency.
    unsafe instance.run(instructions: .setPV(kArbitraryNonzeroVector), .SPVTCA_Y)

    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate()
  }

  // MARK: - SFVTCA 0x04, 0x05
  /*
   Sets the freedom vector to one of the coordinate axes depending on the value of the flag a.
   */

  @Test func testSFVTCA_X() {
    var instance = getInstance()
    // SAFETY: kArbitraryNonzeroVector is a module-level constant; nonisolated(unsafe) is only needed for concurrency.
    unsafe instance.run(instructions: .setFV(kArbitraryNonzeroVector), .SFVTCA_X)

    instance.expectedEngineState.variables.freedomVector = .init(x: 1, y: 0)
    instance.validate()
  }

  @Test func testSFVTCA_Y() {
    var instance = getInstance()
    // SAFETY: kArbitraryNonzeroVector is a module-level constant; nonisolated(unsafe) is only needed for concurrency.
    unsafe instance.run(instructions: .setFV(kArbitraryNonzeroVector), .SFVTCA_Y)

    instance.expectedEngineState.variables.freedomVector = .init(x: 0, y: 1)
    instance.validate()
  }

  // MARK: - SPVTL
  /*
   Changes the direction of the projection vector to that specified by the line defined by the
   endpoints taken from the stack. The order in which the points are specified is significant
   Reversing the order of the points will reverse the direction of the projection vector.

   Pops two point numbers, p2 and p1 and sets the projection vector to a unit vector parallel or
   perpendicular to the line segment from point p2 to point p1 and pointing from p2 to p1.
   */

  @Test func testSPVTL0_X() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: -1, y: 1), at: 0, in: .glyph),
        .setPoint(.init(x: 2, y: 1), at: 0, in: .twilight),
        .PUSHB([0]), .SZP2,
        .PUSHB([0, 0]),
        .SPVTL_0,
      ]
    )

    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.variables.projectionVector = .init(x: -1, y: 0)
    instance.validate(except: [.points])
  }

  @Test func testSPVTL0_Y() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: 1, y: 1), at: 0, in: .twilight),
        .setPoint(.init(x: 1, y: -1), at: 0, in: .glyph),
        .PUSHB([0]), .SZP1,
        .PUSHB([0, 0]),
        .SPVTL_0,
      ]
    )

    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate(except: .points)
  }

  @Test func testSPVTL0_offAxis() throws {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.zero, at: 0, in: .glyph),
        .setPoint(.init(x: 1, y: 2), at: 1, in: .glyph),
        .PUSHB([0, 1]),
        .SPVTL_0,
      ]
    )

    // x: -0.44720458984375, y: -0.8944091796875
    instance.expectedEngineState.variables.projectionVector = .init(
      x: .init(bitPattern: -7_327),
      y: .init(bitPattern: -14_654)
    )
    instance.validate(except: .points)
  }

  @Test func testSPVTL0_offAxisNoTwilightZone() throws {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxElements: 1))
    instance.setPoints([.zero, .init(x: 1, y: 2)], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 1]),
        .SPVTL_0,
      ]
    )

    // x: -0.44720458984375, y: -0.8944091796875
    instance.expectedEngineState.variables.projectionVector = .init(
      x: .init(bitPattern: -7_327),
      y: .init(bitPattern: -14_654)
    )
    instance.validate(except: .points)
  }

  @Test func testSPVTL0_zero() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 0, y: 0),
        OutlinePoint(x: 0, y: 0),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SPVTCA_Y,
        .PUSHB([0, 1]),
        .SPVTL_0,
      ]
    )

    instance.expectedEngineState.variables.projectionVector = .init(x: 1, y: 0)
    instance.validate()
  }

  @Test func testSPVTL1_X() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: -1, y: 1), at: 0, in: .glyph),
        .setPoint(.init(x: 2, y: 1), at: 0, in: .twilight),
        .PUSHB([0]), .SZP2,
        .PUSHB([0, 0]),
        .SPVTL_1,
      ]
    )

    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: -1)
    instance.validate(except: .points)
  }

  @Test func testSPVTL1_Y() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: 1, y: 1), at: 0, in: .twilight),
        .setPoint(.init(x: 1, y: -1), at: 0, in: .glyph),
        .PUSHB([0]), .SZP1,
        .PUSHB([0, 0]),
        .SPVTL_1,
      ]
    )

    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.projectionVector = .init(x: -1, y: 0)
    instance.validate(except: .points)
  }

  @Test func testSPVTL1_offAxis() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.zero, at: 0, in: .glyph),
        .setPoint(.init(x: 1, y: 2), at: 1, in: .glyph),
        .PUSHB([0, 1]),
        .SPVTL_1,
      ]
    )

    // x: -0.8944091796875, y: 0.44720458984375
    instance.expectedEngineState.variables.projectionVector = .init(
      x: .init(bitPattern: 14_654),
      y: .init(bitPattern: -7_327)
    )
    instance.validate(except: .points)
  }

  @Test func testSPVTL1_zero() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 0, y: 0),
        OutlinePoint(x: 0, y: 0),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SPVTCA_X,
        .PUSHB([0, 1]),
        .SPVTL_1,
      ]
    )

    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate()
  }

  @Test func testSPVTL_arithmeticOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: .min, y: .max), at: 0, in: .glyph),
        .setPoint(.init(x: .max, y: .min), at: 1, in: .glyph),
        .SVTCA_X,
        .PUSHB([0, 1]),
        .SPVTL_0,
      ]
    )

    // x: 0.70709228515625, y: -0.70709228515625
    instance.expectedEngineState.variables.projectionVector = .init(
      x: .init(bitPattern: 11_585),
      y: .init(bitPattern: -11_585)
    )
    instance.validate(except: .points)
  }

  @Test func testSPVTL_OOB() {
    runNegativeTest(.glyf, instructions: .PUSHB([99, 0]), .SPVTL_0, failure: .noSuchPoint)
    runNegativeTest(.glyf, instructions: .PUSHB([99, 0]), .SPVTL_1, failure: .noSuchPoint)

    runNegativeTest(.glyf, instructions: .PUSHB([0, 99]), .SPVTL_0, failure: .noSuchPoint)
    runNegativeTest(.glyf, instructions: .PUSHB([0, 99]), .SPVTL_1, failure: .noSuchPoint)
  }

  @Test func testSPVTL_tooFewStackElements() {
    runStackUnderflowTests(.glyf, opcode: .SPVTL_0, parameters: 2)
    runStackUnderflowTests(.glyf, opcode: .SPVTL_1, parameters: 2)
  }

  @Test func testSPVTL_pedanticZoneChecks() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2))
    instance.setPoints([.zero, .zero, .zero, .zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 1]), .SPVTL_1,
      ],
      failure: .maxpLimitExceeded
    )
    instance.validate()
  }

  // MARK: - SFVTL
  /*
   Change the value of the freedom vector using the direction specified by the line whose end
   points are taken from the stack. The effect is to change the direction in which points can move
   to be parallel to that line. The order in which the points are chosen is significant. Reversing
   the order will reverse the direction of the freedom vector.

   Pops two point numbers p2 and p1 from the stack and sets the freedom vector to a unit vector
   parallel or perpendicular to the line segment defined by points p1 and p2 and pointing from p2
   to p1.

   If the Boolean a has the value 0, the freedom vector is parallel to the line from p2 to p1.

   If the Boolean a has the value one, the freedom vector is perpendicular to the line from p2 to
   p1. More precisely, the freedom vector is obtained by rotating the vector that is parallel to
   the line 90 counter clockwise.
   */

  @Test func testSFVTL0_X() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: -1, y: 1), at: 0, in: .glyph),
        .setPoint(.init(x: 2, y: 1), at: 0, in: .twilight),
        .PUSHB([0]), .SZP2,
        .PUSHB([0, 0]),
        .SFVTL_0,
      ]
    )

    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.variables.freedomVector = .init(x: -1, y: 0)
    instance.validate(except: .points)
  }

  @Test func testSFVTL0_Y() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: 1, y: 1), at: 0, in: .twilight),
        .setPoint(.init(x: 1, y: -1), at: 0, in: .glyph),
        .PUSHB([0]), .SZP1,
        .PUSHB([0, 0]),
        .SFVTL_0,
      ]
    )

    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.freedomVector = .init(x: 0, y: 1)
    instance.validate(except: .points)
  }

  @Test func testSFVTL0_offAxis() throws {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.zero, at: 0, in: .glyph),
        .setPoint(.init(x: 1, y: 2), at: 1, in: .glyph),
        .PUSHB([0, 1]),
        .SFVTL_0,
      ]
    )

    // x: -0.44720458984375, y: -0.8944091796875
    instance.expectedEngineState.variables.freedomVector = .init(
      x: .init(bitPattern: -7_327),
      y: .init(bitPattern: -14_654)
    )
    instance.validate(except: .points)
  }

  @Test func testSFVTL0_zero() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 0, y: 0),
        OutlinePoint(x: 0, y: 0),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SFVTCA_Y,
        .PUSHB([0, 1]),
        .SFVTL_0,
      ]
    )

    instance.expectedEngineState.variables.freedomVector = .init(x: 1, y: 0)
    instance.validate()
  }

  @Test func testSFVTL1_X() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: -1, y: 1), at: 0, in: .glyph),
        .setPoint(.init(x: 2, y: 1), at: 0, in: .twilight),
        .PUSHB([0]), .SZP2,
        .PUSHB([0, 0]),
        .SFVTL_1,
      ]
    )

    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.variables.freedomVector = .init(x: 0, y: -1)
    instance.validate(except: .points)
  }

  @Test func testSFVTL1_Y() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: 1, y: 1), at: 0, in: .twilight),
        .setPoint(.init(x: 1, y: -1), at: 0, in: .glyph),
        .PUSHB([0]), .SZP1,
        .PUSHB([0, 0]),
        .SFVTL_1,
      ]
    )

    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.freedomVector = .init(x: -1, y: 0)
    instance.validate(except: .points)
  }

  @Test func testSFVTL1_offAxis() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.zero, at: 0, in: .glyph),
        .setPoint(.init(x: 1, y: 2), at: 1, in: .glyph),
        .PUSHB([0, 1]),
        .SFVTL_1,
      ]
    )

    // x: -0.8944091796875, y: 0.44720458984375
    instance.expectedEngineState.variables.freedomVector = .init(
      x: .init(bitPattern: 14_654),
      y: .init(bitPattern: -7_327)
    )
    instance.validate(except: .points)
  }

  @Test func testSFVTL1_zero() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 0, y: 0),
        OutlinePoint(x: 0, y: 0),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SFVTCA_X,
        .PUSHB([0, 1]),
        .SFVTL_1,
      ]
    )

    instance.expectedEngineState.variables.freedomVector = .init(x: 0, y: 1)
    instance.validate()
  }

  @Test func testSFVTL_arithmeticOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: .min, y: .max),
        OutlinePoint(x: .max, y: .min),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .PUSHB([0, 1]),
        .SFVTL_0,
      ]
    )

    // x: 0.70709228515625, y: -0.70709228515625
    instance.expectedEngineState.variables.freedomVector = .init(
      x: .init(bitPattern: 11_585),
      y: .init(bitPattern: -11_585)
    )
    instance.validate(except: .points)
  }

  @Test func testSFVTL_OOB() {
    runNegativeTest(.glyf, instructions: .PUSHB([99, 0]), .SFVTL_0, failure: .noSuchPoint)
    runNegativeTest(.glyf, instructions: .PUSHB([99, 0]), .SFVTL_1, failure: .noSuchPoint)

    runNegativeTest(.glyf, instructions: .PUSHB([0, 99]), .SFVTL_0, failure: .noSuchPoint)
    runNegativeTest(.glyf, instructions: .PUSHB([0, 99]), .SFVTL_1, failure: .noSuchPoint)
  }

  @Test func testSFVTL_tooFewStackElements() {
    runStackUnderflowTests(.glyf, opcode: .SFVTL_0, parameters: 2)
    runStackUnderflowTests(.glyf, opcode: .SFVTL_1, parameters: 2)
  }

  @Test func testSFVTL_pedanticZoneChecks() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2))
    instance.setPoints([.zero, .zero, .zero, .zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 1]), .SFVTL_1,
      ],
      failure: .maxpLimitExceeded
    )
    instance.validate()
  }

  // MARK: - SPVFS 0x0A
  /*
   Establishes a new value for the projection vector using values taken from the stack.
   Pops two numbers y and x representing the y an x components of the projection vector. The
   values x and y are 2.14 numbers extended to 32 bits. Sets the direction of the projection
   vector, using values x and y taken from the stack, so that its projections onto the x and
   y-axes are x and y, which are specified as signed (two’s complement) fixed-point (2.14)
   numbers. The value (x2 + y2) must be equal to 1 (0x4000).
   Note that the old C interpreter did not check whether the components DO sum to 1, nor did it
   normalize them to ensure it, it just accepted what was on the stack and started doing math.
   */

  @Test func testSPVFS() {
    var instance = getInstance()

    let testVector = FixedVector<F2Dot14>.normalizing(x: 0.8, y: 0.6)

    instance.run(instructions: .NPUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SPVFS)

    instance.expectedEngineState.variables.projectionVector = testVector
    instance.validate()
  }

  @Test func testSPVFS_zeroVector() {
    // When the magnitude is 0, the test-side `normalizing(x:y:)` helper
    // returns the canonical fallback unit vector (1, 0). Drives the
    // `magnitude == 0` branch in `OutlinePoint.swift`'s `normalized()`.
    var instance = getInstance()

    let testVector = FixedVector<F2Dot14>.normalizing(x: 0, y: 0)

    instance.run(instructions: .NPUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SPVFS)

    instance.expectedEngineState.variables.projectionVector = testVector
    instance.validate()
  }

  @Test func testSPVFS_tooFewStackElements() {
    runStackUnderflowTests(opcode: .SPVFS, parameters: 2)
  }

  @Test func testSPVFS_truncating() {
    var instance = getInstance()

    let testVector = FixedVector<F2Dot14>.normalizing(x: 0.8, y: -0.6)

    instance.run(instructions: [
      .pushInt32(Int32(testVector.x.bitPattern)),
      .pushInt32(Int32(testVector.y.bitPattern) + 0x5555_0000),  // truncating should just drop these bits
      .SPVFS,
    ])

    instance.expectedEngineState.stack = []
    instance.expectedEngineState.variables.projectionVector = testVector
    instance.validate()
  }

  // MARK: - SFVFS 0x0B
  /*
   Changes the direction of the freedom vector using values take from the stack and thereby
   changing the direction in which points can move.
   Sets the direction of the freedom vector using the values x and y taken from the stack. The
   vector is set so that its projections onto the x and y -axes are x and y, which are specified
   as signed (two’s complement) fixed-point (2.14) numbers. The value (x2 + y2) must be equal to
   1 (0x4000).
   Note that the old C interpreter did not check whether the components DO sum to 1, nor did it
   normalize them to ensure it, it just accepted what was on the stack and started doing math.
   */

  @Test func testSFVFS() throws {
    var instance = getInstance()

    let testVector = FixedVector<F2Dot14>.normalizing(x: -0.8, y: 0.6)

    instance.run(instructions: .NPUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SFVFS)

    instance.expectedEngineState.variables.freedomVector = testVector
    instance.validate()
  }

  @Test func testSFVFS_tooFewStackElements() {
    runStackUnderflowTests(opcode: .SFVFS, parameters: 2)
  }

  @Test func testSFVFS_truncating() throws {
    var instance = getInstance()

    let testVector = FixedVector<F2Dot14>.normalizing(x: 0.8, y: -0.6)

    instance.run(instructions: [
      .pushInt32(Int32(testVector.x.bitPattern)),
      .pushInt32(Int32(testVector.y.bitPattern) + 0x5555_0000),  // truncating should just drop these bits
      .SFVFS,
    ])

    instance.expectedEngineState.stack = []
    instance.expectedEngineState.variables.freedomVector = testVector
    instance.validate()
  }

  // MARK: - GPV 0x0c
  /*
   Decomposes the current projection vector into its x and y components and puts those components
   on the stack as two 2.14 numbers. The numbers occupy the least significant two bytes of each
   long.
   The first component pushed, px, is the x-component of the projection vector. The second
   pushed, py, is the y-component of the freedom vector. Each is a 2.14 number.
   */

  @Test func testGPV() {
    var instance = getInstance()
    let testVec = FixedVector<F2Dot14>(bitPatternX: 0x2341, y: 0x010a)
    instance.run(instructions: .setPV(testVec), .GPV)

    instance.expectedEngineState.variables.projectionVector = testVec
    instance.expectedEngineState.stack.append(Int32(clamping: testVec.y.bitPattern))
    instance.expectedEngineState.stack.append(Int32(clamping: testVec.x.bitPattern))
    instance.validate()
  }

  // MARK: - GFV 0x0d
  /*
   Decomposes the current freedom vector into its x and y components and puts those components on
   the stack as two 2.14 numbers. The numbers occupy the least significant two bytes of each
   long.
   The first component pushed, px, is the x-component of the freedom vector. The second pushed,
   py, is the y-component of the freedom vector. Each is a 2.14 number.
   */

  @Test func testGFV() {
    var instance = getInstance()
    let testVec = FixedVector<F2Dot14>(bitPatternX: 0x2341, y: 0x010a)
    instance.run(instructions: .setFV(testVec), .GFV)

    instance.expectedEngineState.variables.freedomVector = testVec
    instance.expectedEngineState.stack.append(Int32(clamping: testVec.y.bitPattern))
    instance.expectedEngineState.stack.append(Int32(clamping: testVec.x.bitPattern))
    instance.validate()
  }

  // MARK: - SFVTPV 0x0e
  /*
   Sets the freedom vector to be the same as the projection vector. This means that movement and
   measurement will be in the same direction.
   */

  @Test func testSFVTPV() {
    var instance = getInstance()
    let testVec = FixedVector<F2Dot14>(bitPatternX: 0x2341, y: 0x010a)
    instance.run(instructions: .setPV(testVec), .SFVTPV)

    instance.expectedEngineState.variables.freedomVector = testVec
    instance.expectedEngineState.variables.projectionVector = testVec
    instance.validate()
  }

  @Test func testSFVTPV_rounding() {
    let testVec: FixedVector<F2Dot14> = .init(bitPatternX: 15_063, y: -6_446)
    var instance = getInstance(maxp: .init(maxTwilightPoints: 1))
    instance.run(
      .prep,
      instructions:
          .setPV(testVec),
      .SFVTPV,
      .PUSHB([0, 0]),
      .SZP2,
      .pushF26Dot6(.init(4)),
      .SCFS
    )
    instance.expectedEngineState.variables.freedomVector = testVec
    instance.expectedEngineState.variables.projectionVector = testVec
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.twilightPoints[point: 0] = .init(
      scaled: .init(x: 3.671875, y: -1.578125),
      xMoved: true,
      yMoved: true
    )
    instance.validate()
  }

  // MARK: - ISECT 0x0f
  /*
   Moves the specified point to the intersection of the two lines specified.
   Pops the end points of line A, a0 and a1, followed by the end points of line B, b0 and b1
   followed by point p. Puts point p at the intersection of the lines A and B. The points a0 and
   a1 define line A. Similarly, b0 and b1 define line B. ISECT ignores the freedom vector in
   moving point p.
   */
  @Test func testISECT_1() {
    // use twilight zone
    let a0: OutlinePoint
    let a1: OutlinePoint
    let b0: OutlinePoint
    let b1: OutlinePoint
    let expected_p: OutlinePoint
    a0 = .init(x: 1, y: 1)
    a1 = .init(x: 2, y: 2)
    b0 = .init(x: 1, y: 2)
    b1 = .init(x: 2, y: 1)
    expected_p = .init(scaled: .zero, hinted: .init(x: 1.5, y: 1.5), xMoved: true, yMoved: true)

    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 5))
    instance.setPoints([a0, a1, b0, b1, .zero], forZone: .twilight)
    instance.run(
      .glyf,
      instructions: [
        .NPUSHB([4, 3, 2, 1, 0]),  // push all of the point numbers
        .NPUSHB([0]), .SZPS,  // set all pointers to the twilight zone
        .ISECT,
      ]
    )

    instance.expectedEngineState.twilightPoints[point: 4] = expected_p
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }

  @Test func testISECT_2() {
    let a0: OutlinePoint
    let a1: OutlinePoint
    let b0: OutlinePoint
    let b1: OutlinePoint
    let expected_p: OutlinePoint
    a0 = .init(x: -1, y: -1)
    a1 = .init(x: -2, y: -3)
    b0 = .init(x: -4.25, y: 0)
    b1 = .init(x: 0.75, y: -5)
    expected_p = .init(hinted: .init(x: -1.75, y: -2.5), xMoved: true, yMoved: true)

    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 5))
    instance.setPoints([a0, a1, b0, b1, .zero], forZone: .twilight)
    instance.run(
      .glyf,
      instructions: [
        .NPUSHB([4, 3, 2, 1, 0]),  // push all of the point numbers
        .NPUSHB([0]), .SZPS,  // set all pointers to the twilight zone
        .ISECT,
      ]
    )

    instance.expectedEngineState.twilightPoints[point: 4] = expected_p
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }

  @Test func testISECT_3() {
    let a0: OutlinePoint
    let a1: OutlinePoint
    let b0: OutlinePoint
    let b1: OutlinePoint
    let expected_p: OutlinePoint
    a0 = .init(x: -3.5, y: 3.5)
    a1 = .init(x: 2, y: -1)
    b0 = .init(x: -3.5, y: 0.25)
    b1 = .init(x: 2, y: 2.25)
    expected_p = .init(hinted: .init(x: -0.75, y: 1.25), xMoved: true, yMoved: true)

    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 3, maxTwilightPoints: 2))
    instance.setPoints([a0, a1, .zero], forZone: .glyph)
    instance.setPoints([b0, b1], forZone: .twilight)
    let instructions: [HintingInstruction] = [
      .NPUSHB([2, 1, 0, 1, 0]),  // push all of the point numbers: a0, a1, p in glyph; b0, b1 in twilight
      .NPUSHB([1]), .SZPS,  // set zp0 & zp2 to the glyph zone...
      .NPUSHB([0]), .SZP1,  // ... and zp1 to the twilight zone
      .ISECT,
    ]

    instance.run(.glyf, instructions: instructions)

    instance.expectedEngineState.glyphPoints[point: 2] = expected_p
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .glyph

    instance.validate()
  }

  @Test func testISECT_4_arithmeticOverflow() {
    let a0: OutlinePoint
    let a1: OutlinePoint
    let b0: OutlinePoint
    let b1: OutlinePoint
    a0 = .init(x: .max, y: .max)
    a1 = .init(x: .min, y: .min)
    b0 = .init(x: .max - 3.5, y: .min + 0.25)
    b1 = .init(x: .min + 2, y: .min + 2.25)

    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 3, maxTwilightPoints: 2))
    instance.setPoints([a0, a1, .zero], forZone: .glyph)
    instance.setPoints([b0, b1], forZone: .twilight)
    let instructions: [HintingInstruction] = [
      .NPUSHB([2, 1, 0, 1, 0]),  // push all of the point numbers: a0, a1, p in glyph; b0, b1 in twilight
      .NPUSHB([1]), .SZPS,  // set zp0 & zp2 to the glyph zone...
      .NPUSHB([0]), .SZP1,  // ... and zp1 to the twilight zone
      .ISECT,
    ]

    instance.run(.glyf, instructions: instructions)

    let expected_p: OutlinePoint = .init(
      hinted: .init(x: -33_554_429.609375, y: -33_554_429.609375),
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 2] = expected_p
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .glyph

    instance.validate()
  }

  // Tests a specific combination of values for which F26Dot6 arithmetic yields a significantly
  // different result than F2Dot30
  @Test func testISECT_5_fractVsFixed() {
    let a0: OutlinePoint = .init(hinted: .init(bitPatternX: 192, y: 832))
    let a1: OutlinePoint = .init(hinted: .init(bitPatternX: 1_024, y: 64))
    let b0: OutlinePoint = .init(hinted: .init(bitPatternX: 959, y: 832))
    let b1: OutlinePoint = .init(hinted: .init(bitPatternX: 192, y: 64))
    let expected_p: OutlinePoint = .init(hinted: .init(x: 9.234375, y: 7.25), xMoved: true, yMoved: true)

    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 5))
    instance.setPoints([a0, a1, b0, b1, .zero], forZone: .twilight)
    instance.run(
      .glyf,
      instructions: [
        .NPUSHB([0]), .SZPS,  // set all pointers to the twilight zone
        .NPUSHB([4, 3, 2, 1, 0]),  // push all of the point numbers
        .ISECT,
      ]
    )

    instance.expectedEngineState.twilightPoints[point: 4] = expected_p
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }

  @Test func testISECT_parallel() {
    // In the degenerate case of parallel lines A and B, the point is put in the middle. That is.
    // px = ( (a0x+a1x)/2 + (b0x+b1x)/2 ) / 2
    // py = ( (a0y+a1y)/2 + (b0y+b1y)/2 ) / 2
    let a0: OutlinePoint
    let a1: OutlinePoint
    let b0: OutlinePoint
    let b1: OutlinePoint
    let expected_p: OutlinePoint
    a0 = .init(x: -1, y: -1)
    a1 = .init(x: 1, y: 1)
    b0 = .init(x: 0, y: -1)
    b1 = .init(x: 2, y: 1)
    expected_p = .init(hinted: .init(x: 0.5, y: 0), xMoved: true, yMoved: true)

    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 5))
    instance.setPoints([a0, a1, b0, b1, .zero], forZone: .twilight)
    let instructions: [HintingInstruction] = [
      .NPUSHB([4, 3, 2, 1, 0]),  // push all of the point numbers
      .NPUSHB([0]), .SZPS,  // set all pointers to the twilight zone
      .ISECT,
    ]
    instance.run(.glyf, instructions: instructions)

    instance.expectedEngineState.twilightPoints[point: 4] = expected_p
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }

  @Test func testISECT_aVerticalBHorizontal() {
    // Axis-aligned degenerate: A is a vertical line (dAx == 0, dAy != 0) and B is
    // a horizontal line (dBy == 0). The intersection is (a1.x, b1.y).
    let a0 = OutlinePoint(x: 0, y: -1)
    let a1 = OutlinePoint(x: 0, y: 1)
    let b0 = OutlinePoint(x: -1, y: 0)
    let b1 = OutlinePoint(x: 1, y: 0)
    let expected_p = OutlinePoint(hinted: .init(x: 0, y: 0), xMoved: true, yMoved: true)

    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 5))
    instance.setPoints([a0, a1, b0, b1, .zero], forZone: .twilight)
    let instructions: [HintingInstruction] = [
      .NPUSHB([4, 3, 2, 1, 0]),
      .NPUSHB([0]), .SZPS,
      .ISECT,
    ]
    instance.run(.glyf, instructions: instructions)

    instance.expectedEngineState.twilightPoints[point: 4] = expected_p
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }

  @Test func testISECT_tooFewStackElements() {
    runStackUnderflowTests(
      .glyf,
      opcode: .ISECT,
      parameters: 5
    )
    runNegativeTest(.glyf, instructions: .ISECT, failure: .stackUnderflow)
  }

  @Test func testISECT_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255, 254, 253, 252, 251]), .ISECT,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].move(to: .zero, xMoved: true, yMoved: true)
    instance.validate()
  }

  @Test func testISECT_OOB() {
    // five parameters, but the bottom 1...4 are invalid
    for numElements in 0...4 {
      let invalidParams = Array(repeating: Int16.max, count: numElements + 1)
      let params = invalidParams + Array(repeating: 0, count: 4 - numElements)

      runNegativeTest(.glyf, instructions: .PUSHW(params), .ISECT, failure: .noSuchPoint)
    }
  }

  // MARK: - SRP0 0x10
  /*
   Sets a new value for reference point 0.

   Pops a point number, p, from the stack and sets rp0 to p.
   */

  @Test func testSRP0() {
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([0x1e]), .SRP0])

    instance.expectedEngineState.variables.rp0 = 0x1e
    instance.validate()
  }

  @Test func testSRP0_emptyStack() {
    runStackUnderflowTests(opcode: .SRP0, parameters: 1)
  }

  // MARK: - SRP1 0x11
  /*
   (see description for SRP0)
   */

  @Test func testSRP1() {
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([0x1e]), .SRP1])

    instance.expectedEngineState.variables.rp1 = 0x1e
    instance.validate()
  }

  @Test func testSRP1_emptyStack() {
    runStackUnderflowTests(opcode: .SRP1, parameters: 1)
  }

  // MARK: - SRP2 0x12
  /*
   (see description for SRP0)
   */

  @Test func testSRP2() {
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([0x1e]), .SRP2])

    instance.expectedEngineState.variables.rp2 = 0x1e
    instance.validate()
  }

  @Test func testSRP2_emptyStack() {
    runStackUnderflowTests(opcode: .SRP2, parameters: 1)
  }

  // MARK: - SZP0 0x13
  /*
   Establishes a new value for zp0. It can point to either the glyph zone or the twilight zone.

   Pops a zone number, n, from the stack and sets zp0 to the zone with that number. If n has the
   value zero, zp0 points to zone 0 (the twilight zone). If n has the value one, zp0 points to
   zone 1 (the glyph zone). Any other value for n is an error.
   */

  @Test func testSZP0_twilight() {
    for program in HintingProgram.all {
      var instance = getInstance()
      #expect(instance.engineState().variables.zp0 == .glyph)
      instance.run(program, instructions: [.NPUSHB([0]), .SZP0])

      if program == .fpgm {
        // Test only validates that zone pointers fail lazily
        instance.validate(except: .zonePointers)
      } else {
        instance.expectedEngineState.variables.zp0 = .twilight
        instance.validate()
      }
    }
  }

  @Test func testSZP0_glyph() {
    for program in HintingProgram.all {
      var instance = getInstance()
      #expect(instance.engineState().variables.zp0 == .glyph)
      instance.run(program, instructions: [.NPUSHB([1, 0]), .SZP0, .SZP0])

      if program != .glyf {
        // Test only validates that zone pointers fail lazily
        instance.validate(except: .zonePointers)
      } else {
        instance.expectedEngineState.variables.zp0 = .glyph
        instance.validate()
      }
    }
  }

  @Test func testSZP0_badZone() {
    runNegativeTest(instructions: .PUSHB([2]), .SZP0, failure: .invalidOperand)
  }

  @Test func testSZP0_badZone1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxElements: 1))
    instance.run(
      .glyf,
      instructions: .PUSHB([1]),
      .SZP0,
      failure: .invalidOperand
    )
    instance.validate()
  }

  @Test func testSZP0_emptyStack() {
    runStackUnderflowTests(opcode: .SZP0, parameters: 1)
  }

  // MARK: - SZP1 0x14
  /*
   (see description for SZP0)
   */

  @Test func testSZP1_twilight() {
    for program in HintingProgram.all {
      var instance = getInstance()
      #expect(instance.engineState().variables.zp1 == .glyph)
      instance.run(program, instructions: [.NPUSHB([0]), .SZP1])

      if program == .fpgm {
        // Test only validates that zone pointers fail lazily
        instance.validate(except: .zonePointers)
      } else {
        instance.expectedEngineState.variables.zp1 = .twilight
        instance.validate()
      }
    }
  }

  @Test func testSZP1_glyph() {
    for program in HintingProgram.all {
      var instance = getInstance()
      #expect(instance.engineState().variables.zp1 == .glyph)
      instance.run(program, instructions: [.NPUSHB([1, 0]), .SZP1, .SZP1])

      if program != .glyf {
        // Test only validates that zone pointers fail lazily
        instance.validate(except: .zonePointers)
      } else {
        instance.expectedEngineState.variables.zp1 = .glyph
        instance.validate()
      }
    }
  }

  @Test func testSZP1_badZone() {
    runNegativeTest(instructions: .PUSHB([3]), .SZP1, failure: .invalidOperand)
  }

  @Test func testSZP1_badZone1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxElements: 1))
    instance.run(
      .glyf,
      instructions: .PUSHB([1]),
      .SZP1,
      failure: .invalidOperand
    )
    instance.validate()
  }

  @Test func testSZP1_emptyStack() {
    runStackUnderflowTests(opcode: .SZP1, parameters: 1)
  }

  // MARK: - SZP2 0x15
  /*
   (see description for SZP0)
   */

  @Test func testSZP2_twilight() {
    for program in HintingProgram.all {
      var instance = getInstance()
      #expect(instance.engineState().variables.zp2 == .glyph)
      instance.run(program, instructions: [.NPUSHB([0]), .SZP2])

      if program == .fpgm {
        // Test only validates that zone pointers fail lazily
        instance.validate(except: .zonePointers)
      } else {
        instance.expectedEngineState.variables.zp2 = .twilight
        instance.validate()
      }
    }
  }

  @Test func testSZP2_glyph() {
    for program in HintingProgram.all {
      var instance = getInstance()
      #expect(instance.engineState().variables.zp2 == .glyph)
      instance.run(program, instructions: [.NPUSHB([1, 0]), .SZP2, .SZP2])

      if program != .glyf {
        // Test only validates that zone pointers fail lazily
        instance.validate(except: .zonePointers)
      } else {
        instance.expectedEngineState.variables.zp2 = .glyph
        instance.validate()
      }
    }
  }

  @Test func testSZP2_badZone() {
    runNegativeTest(instructions: .PUSHB([3]), .SZP2, failure: .invalidOperand)
  }

  @Test func testSZP2_badZone1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxElements: 1))
    instance.run(
      .glyf,
      instructions: .PUSHB([1]),
      .SZP2,
      failure: .invalidOperand
    )
    instance.validate()
  }

  @Test func testSZP2_emptyStack() {
    runStackUnderflowTests(opcode: .SZP2, parameters: 1)
  }

  // MARK: - SZPS 0x16
  /*
   (see description for SZP0, this one operates on all three pointers)
   */

  @Test func testSZPS_twilight() {
    for program in HintingProgram.all {
      var instance = getInstance()
      #expect(instance.engineState().variables.zp0 == .glyph)
      #expect(instance.engineState().variables.zp1 == .glyph)
      #expect(instance.engineState().variables.zp2 == .glyph)
      instance.run(program, instructions: [.NPUSHB([0]), .SZPS])

      if program == .fpgm {
        // Test only validates that zone pointers fail lazily
        instance.validate(except: .zonePointers)
      } else {
        instance.expectedEngineState.variables.zp0 = .twilight
        instance.expectedEngineState.variables.zp1 = .twilight
        instance.expectedEngineState.variables.zp2 = .twilight
        instance.validate()
      }
    }
  }

  @Test func testSZPS_glyph() {
    for program in HintingProgram.all {
      var instance = getInstance()
      #expect(instance.engineState().variables.zp0 == .glyph)
      #expect(instance.engineState().variables.zp1 == .glyph)
      #expect(instance.engineState().variables.zp2 == .glyph)
      instance.run(program, instructions: [.NPUSHB([1, 0]), .SZPS, .SZPS])

      if program != .glyf {
        // Test only validates that zone pointers fail lazily
        instance.validate(except: .zonePointers)
      } else {
        instance.expectedEngineState.variables.zp0 = .glyph
        instance.expectedEngineState.variables.zp1 = .glyph
        instance.expectedEngineState.variables.zp2 = .glyph
        instance.validate()
      }
    }
  }

  @Test func testSZPS_badZone() {
    runNegativeTest(instructions: .PUSHB([3]), .SZPS, failure: .invalidOperand)
  }

  @Test func testSZPS_emptyStack() {
    runStackUnderflowTests(opcode: .SZPS, parameters: 1)
  }

  // MARK: - SLOOP 0x17
  @Test func testSLOOP_10() {
    var instance = getInstance()
    instance.run(instructions: [.pushInt32(10), .SLOOP])

    instance.expectedEngineState.variables.loop = 10
    instance.validate()
  }

  // It is illegal according to the spec to push a value less or equal to 0,
  // but the C++ implementation doesn't care and will simply loop 0 times.
  @Test func testSLOOP_0() {
    var instance = getInstance()
    instance.run(instructions: [.pushInt32(0), .SLOOP])

    instance.expectedEngineState.variables.loop = 0
    instance.validate()
  }

  @Test func testSLOOP_minus1() {
    var instance = getInstance()
    instance.run(instructions: [.pushInt32(-1), .SLOOP])

    instance.expectedEngineState.variables.loop = -1
    instance.validate()
  }

  @Test func testSLOOP_intmin() {
    var instance = getInstance()
    instance.run(instructions: [.pushInt32(.min), .SLOOP])

    instance.expectedEngineState.variables.loop = .min
    instance.validate()
  }

  @Test func testSLOOP_emptyStack() {
    runStackUnderflowTests(opcode: .SLOOP, parameters: 1)
  }

  // MARK: - RTG 0x18
  @Test func testRTG_state() {
    var instance = getInstance()
    instance.run(instructions: .setRoundState(.rtg))
    instance.expectedEngineState.variables.roundState = .rtg
    instance.validate()
  }

  @Test func testRTG_state_carries() {
    var instance = getInstance()
    instance.run(.prep, instructions: .setRoundState(.rtg))
    instance.expectedEngineState.variables.roundState = .rtg
    instance.validate()

    instance.run(.glyf, instructions: .SVTCA_X)
    instance.expectedEngineState.variables.roundState = .rtg
    instance.validate()
  }

  @Test func testRTG_rounding() {
    runRoundingTest(roundingMode: .rtg) { value in
      value.roundingIfRepresentable(.toNearestOrAway) ?? 0
    }
  }

  // MARK: - RTHG 0x19
  @Test func testRTHG_state() {
    var instance = getInstance()
    instance.run(instructions: .setRoundState(.rthg))
    instance.expectedEngineState.variables.roundState = .rthg
    instance.validate()
  }

  @Test func testRTHG_rounding() {
    runRoundingTest(roundingMode: .rthg) { value in
      let add: F26Dot6 = value < 0 ? -0.5 : 0.5
      if let rounded = value.roundingIfRepresentable(.towardZero),
         case (let added, false) = rounded.addingReportingOverflow(add) {
        return added
      }
      return add
    }
  }

  // MARK: - SMD
  @Test func testSMD_stackunderflow() {
    runStackUnderflowTests(opcode: .SMD, parameters: 1)
  }

  @Test func testSMD() {
    var instance = getInstance()
    instance.run(instructions: .pushF26Dot6(10), .SMD)
    instance.expectedEngineState.variables.minimumDistance = 10
    instance.validate()
  }

  // MARK: - JMPR 0x1C
  /*
   Moves the instruction pointer to a new location specified by the offset popped from the stack.
   */

  @Test func testJMPR_forward() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 2, 3]),
      .JMPR,  // pops 3
      .CLEAR,  // jumped over
      .CLEAR,  // jumped over
      .DUP,  // executed!
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [2, 2, 1]
    instance.validate()
  }

  @Test func testJMPR_forwardOutOfBounds() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 2, 9]),
      .JMPR,  // pops 9
      .CLEAR,  // jumped over
      // oops, that's the end of the instructions!
    ]

    instance.run(instructions: instructions, failure: .ranOffEndOfInstructions)

    instance.expectedEngineState.stack = [2, 1]
    instance.validate()
  }

  @Test func testJMPR_forwardErrorOutOfBounds() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 2]),
      .pushInt32(.init(UInt16.max) * 3),
      .JMPR,  // pops 9
      .CLEAR,  // jumped over
      // oops, that's the end of the instructions!
    ]

    instance.run(instructions: instructions, failure: .ranOffEndOfInstructions)

    instance.expectedEngineState.stack = [2, 1]
    instance.validate()
  }

  @Test func testJMPR_forward_end() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 9, 2]),
      .JMPR,  // pops 2
      .CLEAR,  // jumped over
      // lands here
    ]

    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [9, 1]
    instance.validate()
  }

  @Test func testJMPR_backwardsOutOfBounds() {
    runNegativeTest(instructions: .NPUSHB([0, 8]), .SUB, .JMPR, failure: .ranOffEndOfInstructions)
  }

  @Test func testJMPR_stackUnderflow() {
    runStackUnderflowTests(opcode: .JMPR, parameters: 1)
  }

  // MARK: - SCVTCI 0x1D
  @Test func testSCVTCI() {
    var instance = getInstance()
    instance.run(instructions: [.pushF26Dot6(10.5), .SCVTCI])
    instance.expectedEngineState.variables.controlValueCutIn = 10.5
    instance.validate()
  }

  // MARK: - SSWCI 0x1E
  @Test func testSSWCI() {
    var instance = getInstance()
    instance.run(instructions: [.pushF26Dot6(10.5), .SSWCI])
    instance.expectedEngineState.variables.singleWidthCutIn = 10.5
    instance.validate()
  }

  @Test func testSSWCI_oob() {
    runStackUnderflowTests(opcode: .SSWCI, parameters: 1)
  }

  // MARK: - SSW 0x1F
  @Test func testSSW() {
    var instance = getInstance()
    instance.run(.notFpgm(), instructions: [.pushInt32(10), .SSW])
    instance.expectedEngineState.variables.singleWidthValue = 2.5
    instance.validate()
  }

  @Test func testSSW_oob() {
    runStackUnderflowTests(.notFpgm(), opcode: .SSW, parameters: 1)
  }

  @Test func testSSW_fpgm() {
    var instance = getInstance()
    instance.run(.fpgm, instructions: [.pushInt32(10), .SSW])
    instance.expectedEngineState.variables.singleWidthValue = 0
    instance.validate()
  }

  @Test func testSSW_truncate() {
    var instance = getInstance()
    instance.run(.notFpgm(), instructions: [.pushInt32(0x7ead_7eef), .SSW])
    instance.expectedEngineState.variables.singleWidthValue = 8_123.75
    instance.validate()
  }

  @Test func testSSW_truncate_neg() {
    var instance = getInstance()
    instance.run(.notFpgm(), instructions: [.pushInt32(0x7ead_beef), .SSW])
    instance.expectedEngineState.variables.singleWidthValue = -4_164.25
    instance.validate()
  }

  // MARK: - DUP 0x20
  /*
   Duplicates the top element on the stack.
   */

  @Test func testDUP() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([42]), .DUP)

    instance.expectedEngineState.stack = [42, 42]
    instance.validate()
  }

  @Test func testDUP_emptyStack() {
    runStackUnderflowTests(opcode: .DUP, parameters: 1)
  }

  // MARK: - POP 0x21
  /*
   Pops the top element from the stack.
   */

  @Test func testPOP() {
    let byte: UInt8 = 0xee
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([byte, 0xff]), .POP])

    instance.expectedEngineState.stack.append(Int32(byte))
    instance.validate()
  }

  @Test func testPOP_emptyStack() {
    runStackUnderflowTests(opcode: .POP, parameters: 1)
  }

  // MARK: - CLEAR 0x22
  /*
   Clears all elements from the stack..
   */

  @Test func testCLEAR() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([42]), .CLEAR)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testCLEAR_emptyStack() {
    var instance = getInstance()
    #expect(instance.engineState().stack.isEmpty)
    instance.run(instructions: .CLEAR)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testCLEAR_bigStack() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB(Array((10...30))), .CLEAR)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  // MARK: - SWAP 0x23
  /*
   Swaps the top two stack elements.

   Pops two elements, e2 and e1, from the stack and reverses their order making the old top
   element the second from the top and the old second element the top element.
   */

  @Test func testSWAP() {
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([0x22, 0x33, 0x44]), .SWAP])

    instance.expectedEngineState.stack.append(contentsOf: [0x33, 0x44, 0x22])
    instance.validate()
  }

  @Test func testSWAP_tooFewStackElements() {
    runStackUnderflowTests(opcode: .SWAP, parameters: 2)
  }

  // MARK: - DEPTH 0x24
  /*
   Pushes n, the number of elements currently in the stack, onto the stack.
   */

  @Test func testDEPTH() {
    // DEPTH can start from an empty stack and will generate the integers!
    var instance = getInstance()
    instance.run(instructions: [
      .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH, .DEPTH,
    ])

    instance.expectedEngineState.stack = [12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0]
    instance.validate()
  }

  // MARK: - CINDEX 0x25
  /*
   Copies the indexed stack element to the top of the stack.
   Pops a stack element number, k, from the stack and pushes a copy of the kth stack element on
   the top of the stack. Since it is a copy that is pushed, the kth element remains in its
   original position. This feature is the key difference between the CINDEX[ ] and MINDEX[ ]
   instructions.
   */
  @Test func testCINDEX() {
    let instructions: [HintingInstruction] = [
      .NPUSHB([4, 12, 6, 13, 1, 12, 5, 3], n: 8),
      .CINDEX,  // CINDEX(3) -> [1, 5, 12, 1, 13, 6, 12, 4]
      .CINDEX,  // CINDEX(1) -> [5, 5, 12, 1, 13, 6, 12, 4]
      .CINDEX,  // CINDEX(5) -> [6, 5, 12, 1, 13, 6, 12, 4]
      .CINDEX,  // CINDEX(6) -> [12, 5, 12, 1, 13, 6, 12, 4]
    ]
    var instance = getInstance()
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [12, 5, 12, 1, 13, 6, 12, 4]
    instance.validate()
  }

  @Test func testCINDEX_emptyStack() {
    runStackUnderflowTests(opcode: .CINDEX, parameters: 1)
  }

  @Test func testCINDEX_zero() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([99, 0]), .CINDEX)

    instance.expectedEngineState.stack = [0, 99]
    instance.validate()
  }

  // An earlier version of CINDEX would halt execution without error instead of continuing
  @Test func testCINDEX_zero_regression() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([99, 0]), .CINDEX, .PUSHB([1]))

    instance.expectedEngineState.stack = [1, 0, 99]
    instance.validate()
  }

  @Test func testCINDEX_negative() {
    runNegativeTest(instructions: .PUSHW([99, -1]), .CINDEX, failure: .stackUnderflow)
  }

  @Test func testCINDEX_oneItemStack() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([99, 1]), .CINDEX)

    instance.expectedEngineState.stack = [99, 99]
    instance.validate()
  }

  @Test func testCINDEX_indexOffEnd() {
    runNegativeTest(instructions: .PUSHB([99, 2]), .CINDEX, failure: .stackUnderflow)
  }

  // MARK: - MINDEX 0x26
  /*
   Moves the indexed element to the top of the stack thereby removing it from its original position.

   Pops an integer, k, from the stack and moves the element with index k to the top of the stack.
   The top element on the stack after the pop has index 1.
   */
  @Test func testMINDEX() {
    let instructions: [HintingInstruction] = [
      .NPUSHB([4, 12, 6, 13, 1, 12, 5, 3], n: 8),
      .MINDEX,  // MINDEX(3) -> [1, 5, 12, 13, 6, 12, 4]
      .MINDEX,  // MINDEX(1) -> [5, 12, 13, 6, 12, 4]
      .MINDEX,  // MINDEX(5) -> [4, 12, 13, 6, 12]
      .MINDEX,  // mindex(4) -> [12, 12, 13, 6]
    ]
    var instance = getInstance()
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [12, 12, 13, 6]
    instance.validate()
  }

  @Test func testMINDEX_emptyStack() {
    runStackUnderflowTests(opcode: .MINDEX, parameters: 1)
  }

  @Test func testMINDEX_zero() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([99, 0]), .MINDEX)

    instance.expectedEngineState.stack = [0, 99]
    instance.validate()
  }

  @Test func testMINDEX_negative() {
    runNegativeTest(
      instructions: .PUSHW([99, -1]),
      .MINDEX,
      expectingProperties: [.stack([-1, 99])],
      failure: .stackUnderflow
    )
  }

  @Test func testMINDEX_oneItemStack() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([99, 1]), .MINDEX)

    instance.expectedEngineState.stack = [99]
    instance.validate()
  }

  @Test func testMINDEX_indexOffEnd() {
    runNegativeTest(
      instructions: .PUSHB([99, 2]),
      .MINDEX,
      expectingProperties: [.stack([2, 99])],
      failure: .stackUnderflow
    )
  }

  // MARK: - ALIGNPTS 0x27
  /*
   Aligns the two points whose numbers are the top two items on the stack along an axis
   orthogonal to the projection vector.
   */

  @Test func testALIGNPTS_X() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let p1 = OutlineCoord(x: 0, y: 1)
    let p2 = OutlineCoord(x: 2, y: -1)
    instance.setPoints(scaled: [p1, p2], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .PUSHB([0, 1]),
        .ALIGNPTS,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: (p2.x + p1.x) / 2, y: p1.y, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: (p2.x + p1.x) / 2, y: p2.y, xMoved: true)
    instance.validate()
  }

  @Test func testALIGNPTS_Y() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let p1 = OutlineCoord(x: 0, y: 1)
    let p2 = OutlineCoord(x: 2, y: -1)
    instance.setPoints(scaled: [p1, p2], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_Y,
        .PUSHB([0, 1]),
        .ALIGNPTS,
        .SVTCA_X,  // Reset vectors to default values
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: p1.x, y: (p2.y + p1.y) / 2, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: p2.x, y: (p2.y + p1.y) / 2, yMoved: true)
    instance.validate()
  }

  @Test func testALIGNPTS_offAxis() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .glyf,
      instructions: [
        .setFV(.normalizing(x: 1, y: 0.5)),  // +30°
        .setPV(.normalizing(x: 0.5, y: 1)),  // +60°
        .setPoint(.zero, at: 0, in: .glyph),
        .setPoint(.init(x: 2, y: 2), at: 1, in: .glyph),
        .PUSHB([0, 1]),
        .ALIGNPTS,
        .SVTCA_X,  // Reset vectors to default values
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1, y: 0, xMoved: true, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1, y: 2, xMoved: true, yMoved: true)
    instance.validate()
  }

  @Test func testALIGNPTS_arithmeticOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 2))

    instance.setPoints([.init(x: .min, y: .max), .init(x: .max, y: .min)], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .PUSHB([0, 1]),
        .ALIGNPTS,
      ],
      failure: .arithmeticError
    )

    instance.validate(except: .points)
  }

  @Test func testALIGNPTS_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255, 254]), .ALIGNPTS,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 254].xMoved = true
    instance.expectedEngineState.glyphPoints[point: 255].xMoved = true
    instance.validate()
  }

  @Test func testALIGNPTS_OOB() {
    runNegativeTest(.glyf, instructions: .PUSHB([99, 0]), .ALIGNPTS, failure: .noSuchPoint)
    runNegativeTest(.glyf, instructions: .PUSHB([99]), .ALIGNPTS, failure: .stackUnderflow)
  }

  @Test func testALIGNPTS_tooFewStackElements() {
    runStackUnderflowTests(.glyf, opcode: .ALIGNPTS, parameters: 2)
  }

  @Test func testALIGNPTS_X_mixingZones() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    let p1 = OutlineCoord(x: 0, y: 1)
    let p2 = OutlineCoord(x: 2, y: -1)
    instance.setPoints(scaled: [p1, .zero], forZone: .glyph)
    instance.setPoints(scaled: [.zero, p2], forZone: .twilight)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .PUSHB([0]), .SZP0,
        .PUSHB([0, 1]),
        .ALIGNPTS,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: (p2.x + p1.x) / 2, y: p1.y, xMoved: true)
    instance.expectedEngineState.twilightPoints[point: 1].moveTo(x: (p2.x + p1.x) / 2, y: p2.y, xMoved: true)

    instance.expectedEngineState.variables.zp0 = .twilight
    instance.validate()
  }

  @Test func testALIGNPTS_Y_mixingZones() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    let p1 = OutlineCoord(x: -1, y: 1)
    let p2 = OutlineCoord(x: 2, y: -1)

    instance.setPoints(scaled: [p1, .zero], forZone: .twilight)
    instance.setPoints(scaled: [.zero, p2], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_Y,
        .PUSHB([0]), .SZP1,
        .PUSHB([0, 1]),
        .ALIGNPTS,
        .SVTCA_X,
      ]
    )

    instance.expectedEngineState.twilightPoints[point: 0].moveTo(x: p1.x, y: (p2.y + p1.y) / 2, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: p2.x, y: (p2.y + p1.y) / 2, yMoved: true)

    instance.expectedEngineState.variables.zp1 = .twilight
    instance.validate()
  }

  @Test func testALIGNPTS_X_OOBWhenMixingZones() {
    var instance = getInstance(maxp: .init(maxPoints: 16, maxTwilightPoints: 32))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: 0, y: 1), at: 15, in: .glyph),
        .setPoint(.init(x: 2, y: -1), at: 31, in: .twilight),
        .SVTCA_X,
        .PUSHB([0]), .SZP0,
        .PUSHB([15, 31]),
        .ALIGNPTS,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.validate(except: [.points])
  }

  @Test func testALIGNPTS_Y_OOBWhenMixingZones() {
    var instance = getInstance(maxp: .init(maxPoints: 32, maxTwilightPoints: 16))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: 2, y: -1), at: 31, in: .glyph),
        .setPoint(.init(x: -1, y: 1), at: 15, in: .twilight),
        .SVTCA_Y,
        .PUSHB([0]), .SZP1,
        .PUSHB([15, 31]),
        .ALIGNPTS,
      ]
    )
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.validate(except: [.points])
  }

  @Test func testALIGNPTS_pedanticZoneChecks1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2, maxTwilightPoints: 16))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0]), .SZP1,
        .PUSHB([2, 2]), .ALIGNPTS,
      ],
      failure: .maxpLimitExceeded
    )
    instance.expectedEngineState.twilightPoints[point: 2].xMoved = true
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.validate()
  }

  @Test func testALIGNPTS_pedanticZoneChecks2() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2, maxTwilightPoints: 16))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0]), .SZP0,
        .PUSHB([2, 2]), .ALIGNPTS,
      ],
      failure: .maxpLimitExceeded
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.validate()
  }

  // MARK: - UTP 0x29
  @Test func testUTP_emptyStack() {
    runStackUnderflowTests(opcode: .UTP, parameters: 1)
  }

  @Test func testUTP_nullFV() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1, xMoved: true, yMoved: true)
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .setFV(.init(x: 0, y: 0)),
        .pushInt32(0),
        .UTP,
      ]
    )
    instance.expectedEngineState.variables.freedomVector = .init(x: 0, y: 0)
    instance.validate()
  }

  @Test func testUTP_xFV() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1, xMoved: true, yMoved: true)
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .setFV(.init(x: 1, y: 0)),
        .pushInt32(0),
        .UTP,
      ]
    )
    instance.expectedEngineState.variables.freedomVector = .init(x: 1, y: 0)
    instance.expectedEngineState.glyphPoints[point: 0] = OutlinePoint(x: 1, y: 1, xMoved: false, yMoved: true)
    instance.validate()
  }

  @Test func testUTP_yFV() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1, xMoved: true, yMoved: true)
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .setFV(.init(x: 0, y: 1)),
        .pushInt32(0),
        .UTP,
      ]
    )
    instance.expectedEngineState.variables.freedomVector = .init(x: 0, y: 1)
    instance.expectedEngineState.glyphPoints[point: 0] = OutlinePoint(x: 1, y: 1, xMoved: true, yMoved: false)
    instance.validate()
  }

  @Test func testUTP_xyFV() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1, xMoved: true, yMoved: true)
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .setFV(.init(x: 1, y: 1)),
        .pushInt32(0),
        .UTP,
      ]
    )
    instance.expectedEngineState.variables.freedomVector = .init(x: 1, y: 1)
    instance.expectedEngineState.glyphPoints[point: 0] = OutlinePoint(x: 1, y: 1, xMoved: false, yMoved: false)
    instance.validate()
  }

  @Test func testUTP_pedanticZoneChecks() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2))
    instance.setPoints([.zero, .zero, .zero, .zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0]), .UTP,
      ],
      failure: .maxpLimitExceeded
    )
    instance.validate()
  }

  // MARK: - LOOPCALL 0x2A
  /*
   Repeatedly calls a function. Pops a function number f and a count. Calls the function, f, count number of times.
   */

  @Test func testLOOPCALL() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .NPUSHB([99]), .ENDF, .PUSHB([3, 0]), .LOOPCALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = [99, 99, 99]
    instance.validate()
  }

  @Test func testLOOPCALL_tooFewStackElements() {
    runNegativeTest(
      .notGlyf(),
      instructions: .PUSHB([0]),
      .FDEF,
      .NPUSHB([99]),
      .ENDF,
      .LOOPCALL,
      failure: .stackUnderflow
    )
    runNegativeTest(
      .notGlyf(),
      instructions: .PUSHB([0]),
      .FDEF,
      .NPUSHB([99]),
      .ENDF,
      .PUSHB([0]),
      .LOOPCALL,
      failure: .stackUnderflow
    )
  }

  @Test func testLOOPCALL_undefinedFunction() {
    // CPP interpreter's behavior when calling an undefined function within
    // the valid range was to just do nothing at all.

    var instance = getInstance(maxp: sfntMaxProfileTable(maxFunctionDefs: 2))
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .NPUSHB([99]), .ENDF,  // define function 0
      .PUSHB([3, 1]), .LOOPCALL,  // call function 1 3 times
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testLOOPCALL_outOfMaxpRangeFunction() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxFunctionDefs: 1))
    instance.run(.glyf, instructions: .PUSHB([1, 0]), .LOOPCALL)
    instance.run(.glyf, instructions: .PUSHB([2, 6]), .LOOPCALL)
    instance.run(.glyf, instructions: .PUSHB([3, 7]), .LOOPCALL, failure: .maxpLimitExceeded)

    instance.expectedEngineState.stack = [3]
    instance.validate()
  }

  @Test func testLOOPCALL_negativeFunction() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxFunctionDefs: 1))
    instance.run(.glyf, instructions: .PUSHW([3, -7]), .LOOPCALL, failure: .maxpLimitExceeded)

    instance.expectedEngineState.stack = [3]
    instance.validate()
  }

  @Test func testLOOPCALL_zeroReps() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .NPUSHB([99]), .ENDF, .PUSHB([0, 0]), .LOOPCALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testLOOPCALL_zeroReps_outOfMaxpRangeFunction() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 1))
    let instructions: [HintingInstruction] = [
      .PUSHB([0, 7]), .LOOPCALL,
    ]
    instance.run(.notGlyf(), instructions: instructions, failure: .maxpLimitExceeded)

    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  // MARK: - CALL 0x2B, FDEF 0x2C, ENDF 0x2D
  /*
   CALL: Calls the function identified by the number of the top of the stack. Pops a function
   identifier number, f, from the stack and calls the function identified by f. The instructions
   contained in the function body will be executed. When execution of the function is complete,
   the instruction pointer will move to the next location in the instruction stream where
   execution of instructions will resume.
   FDEF: Marks the start of a function definition and pops a number, f, from the stack to
   uniquely identify this function. That definition will terminate when an ENDF[] is encountered
   in the instruction stream. A function definition can appear only in the font program or the
   CVT program. Functions must be defined before they can be used with a CALL[ ] instruction.
   ENDF: Marks the end of a function definition or an instruction definition. Function
   definitions and instruction definitions cannot be nested.
   */

  @Test func testFDEF_simple() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 1))
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .NPUSHB([99]), .ENDF,
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testFDEF_safeMargin() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 0))
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([0]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([1]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([2]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([1]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([2]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([3]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([4]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([5]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([3]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([4]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([5]), .FDEF, .NPUSHB([4]), .ENDF,
      .PUSHB([5]), .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testFDEF_safeMarginFail() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 0))
    instance.run(.notGlyf(), instructions: [.PUSHB([6]), .FDEF, .NPUSHB([4]), .ENDF], failure: .maxpLimitExceeded)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testFDEF_negativeNumber() {
    runNegativeTest(
      .notGlyf(),
      instructions: .PUSHW([-1]),
      .FDEF,
      .NPUSHB([99]),
      .ENDF,
      failure: .maxpLimitExceeded
    )
  }

  @Test func testFDEF_glyf() {
    runNegativeTest(
      .glyf,
      instructions: .PUSHW([0]),
      .FDEF,
      .NPUSHB([99]),
      .ENDF,
      failure: .definitionsNotAllowedInGlyf
    )
  }

  @Test func testFDEF_nestedFDEF() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 2))
    instance.run(
      .notGlyf(),
      instructions: .PUSHB([1, 0]),
      .FDEF,
      .NPUSHB([99]),
      .FDEF,
      .ENDF,
      .ENDF,
      failure: .definitionsCannotBeNested
    )

    instance.expectedEngineState.stack = [1]
    instance.validate()
  }

  @Test func testFDEF_nestedIDEF() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 1, maxInstructionDefs: 1))
    instance.run(
      .notGlyf(),
      instructions: .PUSHB([0x90, 0]),
      .FDEF,
      .IDEF,
      .ENDF,
      .ENDF,
      failure: .definitionsCannotBeNested
    )

    instance.expectedEngineState.stack = [0x90]
    instance.validate()
  }

  @Test func testFDEF_emptyFunction() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 1))

    instance.run(.notGlyf(), instructions: .PUSHB([0]), .FDEF, .ENDF, .PUSHB([0]), .CALL)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testFDEF_emptyFunctionMissingENDF() {
    runNegativeTest(.notGlyf(), instructions: .PUSHB([0]), .FDEF, failure: .ranOffEndOfInstructions)
  }

  @Test func testENDF_unexpected() {
    runNegativeTest(.notGlyf(), instructions: .ENDF, failure: .unexpectedENDF)
  }

  @Test func testFDEF_missingENDF() {
    runNegativeTest(.notGlyf(), instructions: .PUSHB([0]), .FDEF, .NPUSHB([99]), failure: .ranOffEndOfInstructions)
  }

  @Test func testFDEF_redefine() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .NPUSHB([99]), .ENDF,
      .PUSHB([0]), .FDEF, .NPUSHB([42]), .ENDF,
      .PUSHB([0]), .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testFDEF_persistsBetweenPrograms() throws {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 2))

    instance.run(.fpgm, instructions: .PUSHB([0]), .FDEF, .PUSHB([45]), .ENDF)

    instance.expectedEngineState = nil
    instance.run(.prep, instructions: .PUSHB([1]), .FDEF, .PUSHB([32]), .ENDF, .PUSHB([0]), .CALL)
    instance.expectedEngineState.stack = [45]
    instance.validate()

    instance.run(.glyf, instructions: .PUSHB([0]), .CALL, .PUSHB([1]), .CALL)

    instance.expectedEngineState.stack = [32, 45]
    instance.validate()
  }

  @Test func testFDEF_pushingSuspiciousBytes() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 1))
    let stackBytes: [UInt8] = [
      HintingInstruction.ENDF.opcode, HintingInstruction.IDEF.opcode, HintingInstruction.FDEF.opcode,
    ]
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .PUSHB(stackBytes), .ENDF,
      .PUSHB([0]), .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = stackBytes.reversed().map(Int32.init)
    instance.validate()
  }

  @Test func testCALL_simple() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF,  // begin def func 0
      .DUP,
      .DUP,
      .ENDF,  // end def func 0
      .PUSHB([42]),
      .PUSHB([0]),
      .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)
    instance.expectedEngineState.stack = [42, 42, 42]
    instance.validate()
  }

  @Test func testCALL_redefined() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .NPUSHB([99]), .ENDF,
      .PUSHB([0]), .FDEF, .NPUSHB([42]), .ENDF,
      .PUSHB([0]), .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testCALL_skipNPUSHB() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF,  // begin def func 0
      .DUP,
      .NPUSHB([0x2C, 0x2C, 0x2C]),  // FDEF
      .DUP,
      .ENDF,  // end def func 0
      .PUSHB([99]),
      .PUSHB([0]),
      .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)
    instance.expectedEngineState.stack = [0x2C, 0x2C, 0x2C, 0x2C, 99, 99]
    instance.validate()
  }

  @Test func testCALL_skipPUSHB() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF,  // begin def func 0
      .DUP,
      .PUSHB([0x2C, 0x2C, 0x2C]),  // FDEF
      .DUP,
      .ENDF,  // end def func 0
      .PUSHB([99]),
      .PUSHB([0]),
      .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)
    instance.expectedEngineState.stack = [0x2C, 0x2C, 0x2C, 0x2C, 99, 99]
    instance.validate()
  }

  @Test func testCALL_skipNPUSHW() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF,  // begin def func 0
      .DUP,
      .NPUSHW([0x2C00, -32_768, 0x002C]),  // FDEF, 0x80000000, FDEF
      .DUP,
      .ENDF,  // end def func 0
      .PUSHB([99]),
      .PUSHB([0]),
      .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)
    instance.expectedEngineState.stack = [0x2C, 0x2C, -32_768, 0x2C00, 99, 99]
    instance.validate()
  }

  @Test func testCALL_skipPUSHW() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF,  // begin def func 0
      .DUP,
      .PUSHW([0x2C00, -32_768, 0x002C]),  // FDEF, 0x80000000, FDEF
      .DUP,
      .ENDF,  // end def func 0
      .PUSHB([99]),
      .PUSHB([0]),
      .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)
    instance.expectedEngineState.stack = [0x2C, 0x2C, -32_768, 0x2C00, 99, 99]
    instance.validate()
  }

  @Test func testCALL_Factorial5() {
    var instance = getInstance()

    let factorial: [HintingInstruction] = [
      // function: compute factorial, recursively
      // pops: N
      // pushes: N! == ( (N-1 != 0) ? (N * fact(N-1)) : 1 )

      .PUSHB([0]), .FDEF,  // begin def func 0

        .DUP,  // [N, N]
      .pushF26Dot6(1),  // [1, N, N]
      .SUB,  // [N-1, N]
      .DUP,  // [N-1, N-1, N]

        .IF,  // [N-1, N]

        .PUSHB([0]),  // [0, N-1, N]
      .CALL,  // recursively call function 0... [N, (N-1)!]

        .MUL,  // [ N! ]

        .ELSE,  // taken iff [N-1=0, N=1] coming from IF

        .POP,  // [N=1]

        .EIF,  // [N!] coming from either way
      .ENDF,  // end def func 0
    ]
    instance.run(.notGlyf(), instructions: factorial + [.pushF26Dot6(5.0), .PUSHB([0]), .CALL])

    instance.expectedEngineState.stack = [F26Dot6(120).bitPattern]
    instance.validate()
  }

  @Test func testCALL_factorial5NoIfElse() {
    var instance = getInstance()

    let factorial: [HintingInstruction] = [
      // function: compute factorial, recursively, without using IF/ELSE
      // I only wrote this test because I implemented CALL before IF/ELSE,
      // so I had to do it this way.
      // pops: N
      // pushes: N! == ( (N == 1) ? 1 : (N * fact(N-1)) )

      .PUSHB([0]), .FDEF,  // begin def func 0, stack at input [N]

        .DUP,  // [N, N]
      .pushF26Dot6(1.0),  // [1, N, N]
      .SUB,  // [N-1, N]
      .DUP,  // [N-1, N-1, N]

        .PUSHB([8]),  // [8, N-1, N-1, N]
      .SWAP,  // [N-1, 8, N-1, N]
      .JROF,  // [N-1, N] , if N-1 is already 0, just return (jump 8 forward to the POP below)

        .PUSHB([0]),  // [0, N-1, N],
      .CALL,  // recursively call function 0... [(N-1)!, N]

        .MUL,  // [ N! ]

        .PUSHB([2]),  // [ 2, N!]
      .JMPR,  // skip the POP right after this

      // when the JROF gets here, we have [N-1=0, N=1] on the stack. We actually want just [N=1]. So, pop the 0.
        .POP,  // [N=1]

      // since i haven't implemented IF/ELSE yet, i have to JROF to valid instructions that do
      // nothing and run to the end of the instruction list, so here it is
        .PUSHB([0x99]),  // [ 153, N! ]
      .POP,  // [ N! ]

        .ENDF,  // end def func 0
    ]
    instance.run(.notGlyf(), instructions: factorial + [.pushF26Dot6(5), .PUSHB([0]), .CALL])

    instance.expectedEngineState.stack = [F26Dot6(120).bitPattern]
    instance.validate()
  }

  @Test func testCALL_infiniteRecursion() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 1))
    instance.run(
      .notGlyf(),
      instructions:
          .PUSHB([0]),
      .FDEF,
      .PUSHB([0, 0]),
      .CALL,
      .ENDF,
      .PUSHB([0]),
      .CALL,
      failure: .callStackTooDeep
    )

    // Final recursion depth is measured by the number of additional 0s pushed to the stack by the function
    instance.expectedEngineState.stack = .init(repeating: 0, count: 64)  // kMaxAllowedRecursivity
    instance.validate()
  }

  @Test func testCALL_emptyStack() {
    runNegativeTest(
      .notGlyf(),
      instructions: .PUSHB([0]),
      .FDEF,
      .NPUSHB([99]),
      .ENDF,
      .CALL,
      failure: .stackUnderflow
    )
  }

  @Test func testCALL_undefinedFunction() {
    // CPP interpreter's behavior when calling an undefined function within
    // the valid range was to just do nothing at all.

    var instance = getInstance(maxp: sfntMaxProfileTable(maxFunctionDefs: 2))
    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .FDEF, .NPUSHB([99]), .ENDF,
      .PUSHB([1]), .CALL,
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testCALL_negativeFunction() {
    runNegativeTest(.notGlyf(), instructions: .PUSHW([-1]), .CALL, .NPUSHB([99]), failure: .invalidOperand)
  }

  @Test func testCALL_outOfMaxpRangeFunction() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxFunctionDefs: 1))
    instance.run(.glyf, instructions: .PUSHB([0]), .CALL)
    instance.run(.glyf, instructions: .PUSHB([6]), .CALL)
    instance.run(.glyf, instructions: .PUSHB([7]), .CALL, failure: .maxpLimitExceeded)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  // MARK: - IUP 0x30, 0x31
  // IUP_X/IUP_Y dispatch through `withZP2`, which gates on `zone.isPresent` and throws
  // `.invalidAccessToGlyphZone` when the glyph zone is empty (sentinel storage). These
  // tests pin that contract — the gate is what keeps `AxisCoords.init` from dereferencing
  // the sentinel `_element` pointer, so it must remain in place.
  @Test func testIUP_X_emptyGlyphZone_throwsInvalidAccess() {
    runNegativeTest(.notGlyf(), instructions: .IUP_X, failure: .invalidAccessToGlyphZone)
  }

  @Test func testIUP_Y_emptyGlyphZone_throwsInvalidAccess() {
    runNegativeTest(.notGlyf(), instructions: .IUP_Y, failure: .invalidAccessToGlyphZone)
  }

  // Pins the `.twilight` arm of `State.withZP`'s sentinel-zone gate. fpgm runs
  // without a twilight zone, so directing FLIPPT through ZP0=twilight forces
  // `withZP0 -> withZP(.twilight)` to throw `.invalidAccessToTwilightZone`.
  @Test func testFLIPPT_emptyTwilightZone_throwsInvalidAccess() {
    runNegativeTest(
      .fpgm,
      instructions: .PUSHB([0]), .SZP0, .PUSHB([0]), .FLIPPT,
      failure: .invalidAccessToTwilightZone
    )
  }

  @Test func testIUP_noop_badContour() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints([.init(x: 1.125, y: -3.25)], forZone: .glyph)
    instance.setContours([0..<12], forZone: .glyph)
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X], failure: .invalidOperand)
    instance.validate()
  }

  @Test func testIUP_noop_onePoint_touched() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25, xMoved: true)
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.validate()
  }

  @Test func testIUP_noop_onePoint_notTouched() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25, xMoved: false)
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.validate()
  }

  @Test func testIUP_noop_allPointsTouched() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25, xMoved: true),
        .init(x: 44.125, y: 33.25, xMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.validate()
  }

  @Test func testIUP_noop_noPointTouched() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25),
        .init(x: 44.125, y: 33.25),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.validate()
  }

  @Test func testIUP_partial_signedContour() {
    var instance = getInstance(
      maxp: .init(
        version: 65_536,
        numGlyphs: 17_938,
        maxPoints: .max,
        maxContours: 9,  // 0 -> 9
        maxCompositePoints: 69,
        maxCompositeContours: 0,
        maxElements: 0,
        maxTwilightPoints: 0,
        maxStorage: 0,
        maxFunctionDefs: 0,
        maxInstructionDefs: 0,
        maxStackElements: 0,
        maxSizeOfInstructions: 0,
        maxComponentElements: 0,
        maxComponentDepth: 3
      ),
      cvtCount: 1
    )
    instance.setCVT([0])
    instance.setScaleFactors(
      xStretch: 0,
      yStretch: 0,
      unitsPerEm: 0,
      pointSize: 0,
      cvtScale: 0,
      isRotated: false,
      isStretched: false
    )
    instance.setPoints(
      [
        .init(scaled: .zero, hinted: .init(x: 46_080.0, y: 3.875)),
        .init(scaled: .zero),
        .init(scaled: .zero, hinted: .init(x: 272.5625, y: 25_690_113.0), yMoved: true),
        .init(
          original: .init(x: 17_733, y: 17_826),
          scaled: .init(x: 72_113.734375, y: 327_680.0),
          hinted: .init(x: -4.0, y: 525_312.0),
          yMoved: true
        ),
        .init(
          original: .init(x: 0, y: -32_768),
          scaled: .init(x: -18_612_224.0, y: 2.671875),
          hinted: .init(x: 20_263_984.0, y: 22_528.0),
          xMoved: true
        ),
        .init(
          scaled: .init(x: 0.0, y: 518.796875),
          hinted: .init(x: 1_024.0, y: 206_848.0),
          onCurve: true,
          xMoved: true
        ),
        .init(
          original: .init(x: 0, y: 435),
          scaled: .init(x: 1_024.0, y: 0.0),
          hinted: .init(x: -14_149_632.0, y: 6_144.0)
        ),
        .init(original: .init(x: 0, y: 14_848), scaled: .zero, hinted: .init(x: 0.0, y: 1.90625)),
        .init(
          original: .init(x: 185, y: 0),
          scaled: .init(x: 32_768.0, y: 0.0),
          hinted: .init(x: 301.171875, y: 19_806_377.171875),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
      ],
      forZone: .glyph
    )
    instance.setContours(
      [
        .init(0...91),
        .init(0...16_640),
        .init(0...(.init(Int16.max))),
        .init(0...(.init(UInt16.max))),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 178,
        177, 177, 172, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 49, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 252, 0, 0, 0, 9, 254, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 91, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 69, 69, 69, 0, 0, 70, 108, 111, 1, 64, 0, 0, 2, 0,
      ].map { .literal($0) },
      failure: .invalidOperand
    )

    #expect(
      instance.engineState().glyphPoints[point: 13]
      == OutlinePoint(
        original: .init(x: 0, y: -7_471),
        scaled: .init(x: -18_612_224.0, y: 163_840.0),
        hinted: .init(x: 20_263_984.0, y: 12_845_056.5)
      )
    )

    instance.expectedEngineState.glyphPoints[point: 13] = .init(
      original: .init(x: 0, y: -7_471),
      scaled: .init(x: -18_612_224.0, y: 163_840.0),
      hinted: .init(x: 20_263_984.0, y: 12_845_056.5)
    )
    instance.expectedEngineState.glyphPoints[point: 14] = .init(
      original: .init(x: 17_733, y: -7_471),
      scaled: .init(x: 72_113.734375, y: 163_840.0),
      hinted: .init(x: 39_646.90625, y: 12_845_056.5)
    )
    instance.expectedEngineState.glyphPoints[point: 15] = .init(
      original: .init(x: 8_866, y: 17_826),
      scaled: .init(x: -9_270_055.125, y: 327_680.0),
      hinted: .init(x: 20_224_075.765625, y: 25_690_113.0)
    )
    instance.expectedEngineState.glyphPoints[point: 16] = .init(
      original: .init(x: 8_866, y: -32_768),
      scaled: .init(x: -18_612_224.0, y: 0.0),
      hinted: .init(x: 20_263_984.0, y: 0.0)
    )
    for i in 17...Int(Int16.max) {
      instance.expectedEngineState.glyphPoints[point: i] = .init(
        scaled: .zero,
        hinted: .init(x: 20_263_984.0, y: 0.0)
      )
    }

    instance.expectedEngineState.variables.autoFlip = false

    instance.validate(except: kErrorExceptions)
  }

  /* BINCOMPAT: The circumstances in play here are:
   * 1. the interpreter error path only rolls back hinted points to their scaled values up to the public phantoms
   * 2. the reference IUP checks contours:
   *    * as they are iterated (some points have already been written)
   *    * against maxPointCount
   * This can leave point modifications outside the outline that can be accessed by subsequent programs.
   *
   * Probably nobody is relying on this in glyph zones, but this could meaningfully affect the twilight zone
   * as it does not follow a rollback mechanism when an opcode fails.
   */
  @Test func testIUP_partial_badContour() {
    var instance = getInstance(
      maxp: .init(
        version: 65_536,
        numGlyphs: 17_938,
        maxPoints: 17_454,
        maxContours: 9,  // 0 -> 9
        maxCompositePoints: 69,
        maxCompositeContours: 0,
        maxElements: 0,
        maxTwilightPoints: 0,
        maxStorage: 0,
        maxFunctionDefs: 0,
        maxInstructionDefs: 0,
        maxStackElements: 0,
        maxSizeOfInstructions: 0,
        maxComponentElements: 0,
        maxComponentDepth: 3
      ),
      cvtCount: 1
    )
    instance.setCVT([0])
    instance.setScaleFactors(
      xStretch: 0,
      yStretch: 0,
      unitsPerEm: 0,
      pointSize: 0,
      cvtScale: 0,
      isRotated: false,
      isStretched: false
    )
    instance.setPoints(
      [
        .init(scaled: .zero, hinted: .init(x: 46_080.0, y: 3.875)),
        .init(scaled: .zero),
        .init(scaled: .zero, hinted: .init(x: 272.5625, y: 25_690_113.0), yMoved: true),
        .init(
          original: .init(x: 17_733, y: 17_826),
          scaled: .init(x: 72_113.734375, y: 327_680.0),
          hinted: .init(x: -4.0, y: 525_312.0),
          yMoved: true
        ),
        .init(
          original: .init(x: 0, y: -32_768),
          scaled: .init(x: -18_612_224.0, y: 2.671875),
          hinted: .init(x: 20_263_984.0, y: 22_528.0),
          xMoved: true
        ),
        .init(
          scaled: .init(x: 0.0, y: 518.796875),
          hinted: .init(x: 1_024.0, y: 206_848.0),
          onCurve: true,
          xMoved: true
        ),
        .init(
          original: .init(x: 0, y: 435),
          scaled: .init(x: 1_024.0, y: 0.0),
          hinted: .init(x: -14_149_632.0, y: 6_144.0)
        ),
        .init(original: .init(x: 0, y: 14_848), scaled: .zero, hinted: .init(x: 0.0, y: 1.90625)),
        .init(
          original: .init(x: 185, y: 0),
          scaled: .init(x: 32_768.0, y: 0.0),
          hinted: .init(x: 301.171875, y: 19_806_377.171875),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
      ],
      forZone: .glyph
    )
    instance.setContours(
      [
        .init(0...91),
        .init(0...16_640),
        .init(0...63_487),
        .init(0...0),
        .init(0...0),
        .init(0...0),
        .init(0...0),
        .init(0...0),
        .init(0...0),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 178,
        177, 177, 172, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 78, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 49, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 252, 0, 0, 0, 9, 254, 255, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 91, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 0, 0, 0, 0, 0, 69, 69, 69, 0, 0, 70, 108, 111, 1, 64, 0, 0, 2, 0,
      ].map { .literal($0) },
      failure: .invalidOperand
    )

    instance.expectedEngineState.glyphPoints[point: 13] = .init(
      original: .init(x: 0, y: -7_471),
      scaled: .init(x: -18_612_224.0, y: 163_840.0),
      hinted: .init(x: 20_263_984.0, y: 12_845_056.5)
    )
    instance.expectedEngineState.glyphPoints[point: 14] = .init(
      original: .init(x: 17_733, y: -7_471),
      scaled: .init(x: 72_113.734375, y: 163_840.0),
      hinted: .init(x: 39_646.90625, y: 12_845_056.5)
    )
    instance.expectedEngineState.glyphPoints[point: 15] = .init(
      original: .init(x: 8_866, y: 17_826),
      scaled: .init(x: -9_270_055.125, y: 327_680.0),
      hinted: .init(x: 20_224_075.765625, y: 25_690_113.0)
    )
    instance.expectedEngineState.glyphPoints[point: 16] = .init(
      original: .init(x: 8_866, y: -32_768),
      scaled: .init(x: -18_612_224.0, y: 0.0),
      hinted: .init(x: 20_263_984.0, y: 0.0)
    )
    for i in 17...16_640 {
      instance.expectedEngineState.glyphPoints[point: i] = .init(
        scaled: .zero,
        hinted: .init(x: 20_263_984.0, y: 0.0)
      )
    }

    instance.expectedEngineState.variables.autoFlip = false

    instance.validate(except: kErrorExceptions)
  }

  @Test func testIUP_X_interp1_middle_ascending() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
        .init(original: .init(x: 65, y: 65)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 16.5, y: 65)
    instance.validate()
  }

  @Test func testIUP_X_interp1_middle_descending() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
        .init(original: .init(x: 65, y: 65)),
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 16.5, y: 65)
    instance.validate()
  }

  @Test func testIUP_Y_interp1_middle() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
        .init(original: .init(x: 65, y: 65)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_Y])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 65, y: 16.5)
    instance.validate()
  }

  @Test func testIUP_interp2_middle() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
        .init(original: .init(x: 25, y: 25)),
        .init(original: .init(x: 65, y: 65)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 12.5, y: 25)
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 16.5, y: 65)
    instance.validate()
  }

  @Test func testIUP_interp1_outsideMin() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
        .init(original: .init(x: -10, y: -10)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 0, y: -10)
    instance.validate()
  }

  @Test func testIUP_interp1_outsideMax() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
        .init(original: .init(x: 120, y: 120)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 40, y: 120)
    instance.validate()
  }

  @Test func testIUP_interp1_middle_twoRuns_distinct() {
    var instance = getInstance(maxp: .init(maxPoints: 6, maxTwilightPoints: 6))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
        .init(original: .init(x: 65, y: 65)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),

          .init(original: .init(x: 10, y: 15), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
        .init(original: .init(x: 15, y: 15)),
        .init(original: .init(x: 60, y: 65), hinted: .init(x: 120, y: 120), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 16.5, y: 65)
    instance.expectedEngineState.glyphPoints[point: 4].moveTo(x: 30, y: 15)
    instance.validate()
  }

  @Test func testIUP_interp1_middle_twoRuns_overlapping() {
    var instance = getInstance(maxp: .init(maxPoints: 6, maxTwilightPoints: 6))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
        .init(original: .init(x: 65, y: 65)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
        .init(original: .init(x: 155, y: 155)),
        .init(original: .init(x: 200, y: 200), hinted: .init(x: 40, y: 40), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 16.5, y: 65)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 31, y: 155)
    instance.validate()
  }

  @Test func testIUP_interp1_middle_wrapEnd() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
        .init(original: .init(x: 65, y: 65)),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 16.5, y: 65)
    instance.validate()
  }

  @Test func testIUP_interp1_middle_wrapBegin() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 65, y: 65)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 20, y: 20), xMoved: true, yMoved: true),
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 10, y: 10), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 16.5, y: 65)
    instance.validate()
  }

  @Test func testIUP_interp1_biggerThan32768_middle() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 34_000, y: 34_000), xMoved: true, yMoved: true),
        .init(original: .init(x: 65, y: 65)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 35_000, y: 35_000), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 34_650, y: 65)
    instance.validate()
  }

  @Test func testIUP_interp1_biggerThan32768_outsideMin() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 34_000, y: 34_000), xMoved: true, yMoved: true),
        .init(original: .init(x: -10, y: -10)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 35_000, y: 35_000), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 33_990, y: -10)
    instance.validate()
  }

  @Test func testIUP_interp1_biggerThan32768_outsideMax() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 34_000, y: 34_000), xMoved: true, yMoved: true),
        .init(original: .init(x: 110, y: -10)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 35_000, y: 35_000), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 35_010, y: -10)
    instance.validate()
  }

  @Test func testIUP_interp1_zeroNumerator() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        .init(original: .init(x: 0, y: 0), hinted: .init(x: 200, y: 200), xMoved: true, yMoved: true),
        .init(original: .init(x: 50, y: 50)),
        .init(original: .init(x: 100, y: 100), hinted: .init(x: 200, y: 200), xMoved: true, yMoved: true),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: [.pushInt32(1), .SZP2, .IUP_X])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 200, y: 50)
    instance.validate()
  }

  @Test func testIUP_braille50Points0To20() {
    var instance = getInstance(
      maxp: .init(
        numGlyphs: 276,
        maxPoints: 160,
        maxContours: 8,
        maxCompositePoints: 0,
        maxCompositeContours: 0,
        maxTwilightPoints: 0,
        maxStorage: 0,
        maxFunctionDefs: 10,
        maxInstructionDefs: 0,
        maxStackElements: 512,
        maxSizeOfInstructions: 403,
        maxComponentElements: 0,
        maxComponentDepth: 0
      )
    )
    instance.setPoints(
      [
        .init(
          original: .init(x: 820, y: 250),
          scaled: .init(x: 12.8125, y: 3.90625),
          hinted: .init(x: 13.0, y: 3.90625),
          onCurve: true,
          xMoved: true
        ),
        .init(original: .init(x: 820, y: 276), scaled: .init(x: 12.8125, y: 4.3125)),
        .init(original: .init(x: 840, y: 321), scaled: .init(x: 13.125, y: 5.015625)),
        .init(original: .init(x: 873, y: 354), scaled: .init(x: 13.640625, y: 5.53125)),
        .init(original: .init(x: 919, y: 374), scaled: .init(x: 14.359375, y: 5.84375)),
        .init(
          original: .init(x: 944, y: 374),
          scaled: .init(x: 14.75, y: 5.84375),
          hinted: .init(x: 14.75, y: 6.0),
          onCurve: true,
          yMoved: true
        ),
        .init(original: .init(x: 970, y: 374), scaled: .init(x: 15.15625, y: 5.84375)),
        .init(original: .init(x: 1_016, y: 354), scaled: .init(x: 15.875, y: 5.53125)),
        .init(original: .init(x: 1_049, y: 321), scaled: .init(x: 16.390625, y: 5.015625)),
        .init(original: .init(x: 1_068, y: 276), scaled: .init(x: 16.6875, y: 4.3125)),
        .init(
          original: .init(x: 1_068, y: 250),
          scaled: .init(x: 16.6875, y: 3.90625),
          hinted: .init(x: 17.0, y: 3.90625),
          onCurve: true,
          xMoved: true
        ),
        .init(original: .init(x: 1_068, y: 225), scaled: .init(x: 16.6875, y: 3.515625)),
        .init(original: .init(x: 1_049, y: 180), scaled: .init(x: 16.390625, y: 2.8125)),
        .init(original: .init(x: 1_016, y: 146), scaled: .init(x: 15.875, y: 2.28125)),
        .init(original: .init(x: 970, y: 127), scaled: .init(x: 15.15625, y: 1.984375)),
        .init(
          original: .init(x: 944, y: 127),
          scaled: .init(x: 14.75, y: 1.984375),
          hinted: .init(x: 14.75, y: 2.0),
          onCurve: true,
          yMoved: true
        ),
        .init(original: .init(x: 919, y: 127), scaled: .init(x: 14.359375, y: 1.984375)),
        .init(original: .init(x: 873, y: 146), scaled: .init(x: 13.640625, y: 2.28125)),
        .init(original: .init(x: 840, y: 180), scaled: .init(x: 13.125, y: 2.8125)),
        .init(original: .init(x: 820, y: 225), scaled: .init(x: 12.8125, y: 3.515625)),
      ],
      forZone: .glyph
    )
    instance.setContours([0..<20], forZone: .glyph)
    instance.run(.glyf, instructions: .IUP_X)
    instance.expectedEngineState.glyphPoints[point: 1] = .init(
      original: .init(x: 820, y: 276),
      scaled: .init(x: 12.8125, y: 4.3125),
      hinted: .init(x: 13.0, y: 4.3125)
    )
    instance.expectedEngineState.glyphPoints[point: 2] = .init(
      original: .init(x: 840, y: 321),
      scaled: .init(x: 13.125, y: 5.015625),
      hinted: .init(x: 13.328125, y: 5.015625)
    )
    instance.expectedEngineState.glyphPoints[point: 3] = .init(
      original: .init(x: 873, y: 354),
      scaled: .init(x: 13.640625, y: 5.53125),
      hinted: .init(x: 13.859375, y: 5.53125)
    )
    instance.expectedEngineState.glyphPoints[point: 4] = .init(
      original: .init(x: 919, y: 374),
      scaled: .init(x: 14.359375, y: 5.84375),
      hinted: .init(x: 14.59375, y: 5.84375)
    )
    instance.expectedEngineState.glyphPoints[point: 5] = .init(
      original: .init(x: 944, y: 374),
      scaled: .init(x: 14.75, y: 5.84375),
      hinted: .init(x: 15.0, y: 6.0),
      onCurve: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 6] = .init(
      original: .init(x: 970, y: 374),
      scaled: .init(x: 15.15625, y: 5.84375),
      hinted: .init(x: 15.421875, y: 5.84375)
    )
    instance.expectedEngineState.glyphPoints[point: 7] = .init(
      original: .init(x: 1_016, y: 354),
      scaled: .init(x: 15.875, y: 5.53125),
      hinted: .init(x: 16.15625, y: 5.53125)
    )
    instance.expectedEngineState.glyphPoints[point: 8] = .init(
      original: .init(x: 1_049, y: 321),
      scaled: .init(x: 16.390625, y: 5.015625),
      hinted: .init(x: 16.6875, y: 5.015625)
    )
    instance.expectedEngineState.glyphPoints[point: 9] = .init(
      original: .init(x: 1_068, y: 276),
      scaled: .init(x: 16.6875, y: 4.3125),
      hinted: .init(x: 17.0, y: 4.3125)
    )
    instance.expectedEngineState.glyphPoints[point: 11] = .init(
      original: .init(x: 1_068, y: 225),
      scaled: .init(x: 16.6875, y: 3.515625),
      hinted: .init(x: 17.0, y: 3.515625)
    )
    instance.expectedEngineState.glyphPoints[point: 12] = .init(
      original: .init(x: 1_049, y: 180),
      scaled: .init(x: 16.390625, y: 2.8125),
      hinted: .init(x: 16.6875, y: 2.8125)
    )
    instance.expectedEngineState.glyphPoints[point: 13] = .init(
      original: .init(x: 1_016, y: 146),
      scaled: .init(x: 15.875, y: 2.28125),
      hinted: .init(x: 16.15625, y: 2.28125)
    )
    instance.expectedEngineState.glyphPoints[point: 14] = .init(
      original: .init(x: 970, y: 127),
      scaled: .init(x: 15.15625, y: 1.984375),
      hinted: .init(x: 15.421875, y: 1.984375)
    )
    instance.expectedEngineState.glyphPoints[point: 15] = .init(
      original: .init(x: 944, y: 127),
      scaled: .init(x: 14.75, y: 1.984375),
      hinted: .init(x: 15.0, y: 2.0),
      onCurve: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 16] = .init(
      original: .init(x: 919, y: 127),
      scaled: .init(x: 14.359375, y: 1.984375),
      hinted: .init(x: 14.59375, y: 1.984375)
    )
    instance.expectedEngineState.glyphPoints[point: 17] = .init(
      original: .init(x: 873, y: 146),
      scaled: .init(x: 13.640625, y: 2.28125),
      hinted: .init(x: 13.859375, y: 2.28125)
    )
    instance.expectedEngineState.glyphPoints[point: 18] = .init(
      original: .init(x: 840, y: 180),
      scaled: .init(x: 13.125, y: 2.8125),
      hinted: .init(x: 13.328125, y: 2.8125)
    )
    instance.expectedEngineState.glyphPoints[point: 19] = .init(
      original: .init(x: 820, y: 225),
      scaled: .init(x: 12.8125, y: 3.515625),
      hinted: .init(x: 13.0, y: 3.515625)
    )
    instance.validate()
  }

  // IUP does *not* check its zone
  @Test func testIUP_pedanticZoneChecks() {
    for instruction in [HintingInstruction.IUP_X, .IUP_Y] {
      var instance = getInstance(maxp: .init(maxPoints: 2))
      instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
      instance.run(.glyf, instructions: instruction)
      instance.validate()
    }
  }

  @Test func testIUP_largeValues() {
    var instance = getInstance(
      maxp: .init(
        numGlyphs: 6,
        maxPoints: 62,
        maxContours: 2,
        maxCompositePoints: 0,
        maxCompositeContours: 0,
        maxElements: 2,
        maxTwilightPoints: 12,
        maxStorage: 6,
        maxFunctionDefs: 22,
        maxInstructionDefs: 0,
        maxStackElements: 154,
        maxSizeOfInstructions: 77,
        maxComponentElements: 0,
        maxComponentDepth: 0
      )
    )
    instance.setPoints(
      [
        OutlinePoint(
          original: .init(x: 693, y: 0),
          scaled: .init(x: 693.0, y: 0.0),
          onCurve: true,
          yMoved: true
        ),  // 0
        OutlinePoint(
          original: .init(x: 693, y: 159),
          scaled: .init(x: 693.0, y: 159.0),
          hinted: .init(x: 692.0, y: 158.84375),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),  // 1
        OutlinePoint(original: .init(x: 645, y: 73), scaled: .init(x: 645.0, y: 73.0)),  // 2
        OutlinePoint(original: .init(x: 489, y: -24), scaled: .init(x: 489.0, y: -24.0)),  // 3
        OutlinePoint(
          original: .init(x: 404, y: -24),
          scaled: .init(x: 404.0, y: -24.0),
          hinted: .init(x: 404.0, y: -25.0),
          onCurve: true,
          yMoved: true
        ),  // 4
        OutlinePoint(original: .init(x: 318, y: -24), scaled: .init(x: 318.0, y: -24.0)),  // 5
        OutlinePoint(original: .init(x: 182, y: 66), scaled: .init(x: 182.0, y: 66.0)),  // 6
        OutlinePoint(original: .init(x: 115, y: 232), scaled: .init(x: 115.0, y: 232.0)),  // 7
        OutlinePoint(
          original: .init(x: 115, y: 390),
          scaled: .init(x: 115.0, y: 390.0),
          onCurve: true,
          xMoved: true
        ),  // 8
        OutlinePoint(
          original: .init(x: 115, y: 1_062),
          scaled: .init(x: 115.0, y: 1_062.0),
          onCurve: true,
          yMoved: true
        ),  // 9
        OutlinePoint(
          original: .init(x: 346, y: 1_062),
          scaled: .init(x: 346.0, y: 1_062.0),
          onCurve: true,
          yMoved: true
        ),  // 10
        OutlinePoint(
          original: .init(x: 346, y: 574),
          scaled: .init(x: 346.0, y: 574.0),
          onCurve: true,
          xMoved: true
        ),  // 11
        OutlinePoint(original: .init(x: 346, y: 365), scaled: .init(x: 346.0, y: 365.0)),  // 12
        OutlinePoint(original: .init(x: 367, y: 252), scaled: .init(x: 367.0, y: 252.0)),  // 13
        OutlinePoint(original: .init(x: 439, y: 190), scaled: .init(x: 439.0, y: 190.0)),  // 14
        OutlinePoint(
          original: .init(x: 490, y: 190),
          scaled: .init(x: 490.0, y: 190.0),
          onCurve: true,
          yMoved: true
        ),  // 15
        OutlinePoint(original: .init(x: 548, y: 190), scaled: .init(x: 548.0, y: 190.0)),  // 16
        OutlinePoint(original: .init(x: 646, y: 271), scaled: .init(x: 646.0, y: 271.0)),  // 17
        OutlinePoint(original: .init(x: 677, y: 398), scaled: .init(x: 677.0, y: 398.0)),  // 18
        OutlinePoint(
          original: .init(x: 677, y: 614),
          scaled: .init(x: 677.0, y: 614.0),
          hinted: .init(x: 676.0, y: 614.0),
          onCurve: true,
          xMoved: true
        ),  // 19
        OutlinePoint(
          original: .init(x: 677, y: 1_062),
          scaled: .init(x: 677.0, y: 1_062.0),
          onCurve: true,
          yMoved: true
        ),  // 20
        OutlinePoint(
          original: .init(x: 907, y: 1_062),
          scaled: .init(x: 907.0, y: 1_062.0),
          onCurve: true,
          yMoved: true
        ),  // 21
        OutlinePoint(
          original: .init(x: 907, y: 0),
          scaled: .init(x: 907.0, y: 0.0),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),  // 22
      ],
      forZone: .glyph
    )
    instance.setContours([0..<24], forZone: .glyph)
    instance.run(.glyf, instructions: .IUP_X)
    instance.expectedEngineState.glyphPoints[point: 0] = .init(
      original: .init(x: 693, y: 0),
      scaled: .init(x: 693.0, y: 0.0),
      hinted: .init(x: 692.0, y: 0.0),
      onCurve: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 2] = .init(
      original: .init(x: 645, y: 73),
      scaled: .init(x: 645.0, y: 73.0),
      hinted: .init(x: 644.078125, y: 73.0)
    )
    instance.expectedEngineState.glyphPoints[point: 3] = .init(
      original: .init(x: 489, y: -24),
      scaled: .init(x: 489.0, y: -24.0),
      hinted: .init(x: 488.359375, y: -24.0)
    )
    instance.expectedEngineState.glyphPoints[point: 4] = .init(
      original: .init(x: 404, y: -24),
      scaled: .init(x: 404.0, y: -24.0),
      hinted: .init(x: 403.5, y: -25.0),
      onCurve: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 5] = .init(
      original: .init(x: 318, y: -24),
      scaled: .init(x: 318.0, y: -24.0),
      hinted: .init(x: 317.65625, y: -24.0)
    )
    instance.expectedEngineState.glyphPoints[point: 6] = .init(
      original: .init(x: 182, y: 66),
      scaled: .init(x: 182.0, y: 66.0),
      hinted: .init(x: 181.890625, y: 66.0)
    )
    instance.expectedEngineState.glyphPoints[point: 13] = .init(
      original: .init(x: 367, y: 252),
      scaled: .init(x: 367.0, y: 252.0),
      hinted: .init(x: 366.9375, y: 252.0)
    )
    instance.expectedEngineState.glyphPoints[point: 14] = .init(
      original: .init(x: 439, y: 190),
      scaled: .init(x: 439.0, y: 190.0),
      hinted: .init(x: 438.71875, y: 190.0)
    )
    instance.expectedEngineState.glyphPoints[point: 15] = .init(
      original: .init(x: 490, y: 190),
      scaled: .init(x: 490.0, y: 190.0),
      hinted: .init(x: 489.5625, y: 190.0),
      onCurve: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 16] = .init(
      original: .init(x: 548, y: 190),
      scaled: .init(x: 548.0, y: 190.0),
      hinted: .init(x: 547.390625, y: 190.0)
    )
    instance.expectedEngineState.glyphPoints[point: 17] = .init(
      original: .init(x: 646, y: 271),
      scaled: .init(x: 646.0, y: 271.0),
      hinted: .init(x: 645.09375, y: 271.0)
    )
    instance.expectedEngineState.glyphPoints[point: 18] = .init(
      original: .init(x: 677, y: 398),
      scaled: .init(x: 677.0, y: 398.0),
      hinted: .init(x: 676.0, y: 398.0)
    )
    instance.expectedEngineState.glyphPoints[point: 20] = .init(
      original: .init(x: 677, y: 1_062),
      scaled: .init(x: 677.0, y: 1_062.0),
      hinted: .init(x: 676.0, y: 1_062.0),
      onCurve: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 23] = .init(
      original: .init(x: 115, y: 519),
      scaled: .init(x: 115.0, y: 519.0),
      hinted: .init(x: 114.0, y: 518.5)
    )
    instance.validate()
  }

  // MARK: - SHP 0x32, 0x33
  @Test func testSHP0_noop() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints([.init(x: 1.125, y: -3.25)], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(0), .SLOOP,
        .SHP_0,
      ]
    )
    instance.validate()
  }

  @Test func testSHP0_missing_reference_point() {
    runNegativeTest(
      .glyf,
      instructions: [
        .pushInt32(0), .SLOOP,
        .pushInt32(100), .SRP2,
        .SHP_0,
      ],
      expectingProperties: [
        .variable(\.loop, 0),
        .variable(\.rp2, 100),
      ],
      failure: .noSuchPoint
    )
  }

  @Test func testSHP0_missing_loop_point() {
    runNegativeTest(
      .glyf,
      twilightPoints: [.zero],
      glyphPoints: [.zero],
      instructions: [.pushInt32(10), .SHP_0],
      failure: .noSuchPoint
    )
  }

  @Test func testSHP0_one_point() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      hinted: [
        .init(x: 1.125, y: -3.25),
        .init(x: 2, y: -4),
      ],
      scaled: [
        .init(x: 0.5, y: -2),
        .init(x: 2, y: -4),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SHP_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2.625, y: -4, xMoved: true)
    instance.validate()
  }

  @Test func testSHP1_two_points() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxTwilightPoints: 4))
    instance.setPoints(
      hinted: [
        .init(x: 1.125, y: -3.25),
        .init(x: 2, y: -4),
        .init(x: 0, y: 1.5),
      ],
      scaled: [
        .init(x: 0.5, y: -2),
        .init(x: 2, y: -4),
        .init(x: 2, y: 1.25),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2), .SRP2,
        .pushInt32(2), .SLOOP,
        .pushInt32(0), .pushInt32(1), .SHP_1,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1.75, y: -3.25, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2.625, y: -4, xMoved: true)
    instance.expectedEngineState.variables.rp2 = 2
    instance.validate()
  }

  @Test func testSHP_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max), cvtCount: 256)
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255, 255]), .SRP2, .SHP_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].xMoved = true
    instance.expectedEngineState.variables.rp2 = 255
    instance.validate()
  }

  // reference point: rp2 in zp1
  @Test func testSHP0_usesCorrectZonesAndPoints() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxTwilightPoints: 4))
    instance.setPoints(
      hinted: [
        .init(x: 0, y: 1.5)
      ],
      scaled: [
        .init(x: 2, y: 1.25)
      ],
      forZone: .glyph
    )
    instance.setPoints(
      hinted: [
        .init(x: 1.125, y: -3.25)
      ],
      scaled: [
        .init(x: 0.5, y: -2)
      ],
      forZone: .twilight
    )

    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 0, 99, 99, 0, 1]), .SZPS, .SZP1, .SRP0, .SRP1, .SRP2,
        .SHP_0,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 0.625, y: 1.5, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 99
    instance.expectedEngineState.variables.rp1 = 99
    instance.expectedEngineState.variables.rp2 = 0
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .glyph
    instance.validate()
  }

  // reference point: rp1 in zp0
  @Test func testSHP1_usesCorrectZonesAndPoints() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxTwilightPoints: 4))
    instance.setPoints(
      hinted: [
        .init(x: 0, y: 1.5)
      ],
      scaled: [
        .init(x: 2, y: 1.25)
      ],
      forZone: .glyph
    )
    instance.setPoints(
      hinted: [
        .init(x: 1.125, y: -3.25)
      ],
      scaled: [
        .init(x: 0.5, y: -2)
      ],
      forZone: .twilight
    )

    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 99, 0, 99, 0, 1]), .SZPS, .SZP0, .SRP0, .SRP1, .SRP2,
        .SHP_1,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 0.625, y: 1.5, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 99
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 99
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.zp2 = .glyph
    instance.validate()
  }

  // The reference implementation of SHP inlined its own implementation of MovePoint that is less pedantic
  @Test func testSHP_pedanticZoneChecks() {
    for instruction in [HintingInstruction.SHP_0, .SHP_1] {
      var instance = getInstance(maxp: .init(maxPoints: 2))
      instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
      instance.run(
        .glyf,
        instructions: [
          .PUSHB([0]), instruction,
        ]
      )
      instance.validate(except: .points)
    }
  }

  // the reference interpreter's inlined MovePoint also permits integer overflow
  @Test func testSHP_movePointOverflowDoesNotError() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      hinted: [
        .init(x: .max, y: .min),
        .init(x: 1_000, y: -1_000),
      ],
      scaled: [
        .init(x: 0, y: 0),
        .init(x: 2, y: -4),
      ],
      forZone: .glyph
    )

    instance.run(
      .glyf,
      instructions: [
        .setFV(.init(x: .max, y: .max)),
        .pushInt32(1), .SHP_0,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 1].moveTo(
      x: -33_553_432.015625,
      y: 33_553_431.984375,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.variables.freedomVector = .init(x: .max, y: .max)
    instance.validate()
  }

  // MARK: - SHC 0x34, 0x35
  @Test func testSHC0_missingReferencePoint() {
    runNegativeTest(
      .glyf,
      instructions: [
        .pushInt32(100), .SRP2,
        .pushInt32(0), .SHC_0,
      ],
      expectingProperties: [.stack([0]), .variable(\.rp2, 100)],
      failure: .noSuchPoint
    )
  }

  @Test func testSHC0_missingContour() {
    let instructions: [HintingInstruction] = [.pushInt32(0), .SRP2, .pushInt32(1), .SHC_0]
    runNegativeTest(
      .notGlyf(),
      instructions: instructions,
      expectingProperties: [.stack([1])],
      failure: .invalidAccessToGlyphZone
    )
    runNegativeTest(.glyf, instructions: instructions, failure: .noSuchContour)
  }

  @Test func testSHC0_oneContour_includesReferencePoint() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      [
        .init(scaled: .init(x: 0.5, y: -2), hinted: .init(x: 1.125, y: -3.25)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2, y: -4)),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(0), .SHC_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2.625, y: -4, xMoved: true)
    instance.validate()
  }

  @Test func testSHC0_twoContours() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 0.5, y: -2), hinted: .init(x: 1.125, y: -3.25)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2, y: -4)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([0..<2, 2..<4], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SHC_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 1.625, y: -5, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 1.625, y: -6, xMoved: true)
    instance.validate()
  }

  @Test func testSHC0_badContour() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 0.5, y: -2), hinted: .init(x: 1.125, y: -3.25)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2, y: -4)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([0..<2, 2..<13], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SHC_0,
      ],
      failure: .invalidOperand
    )
    instance.validate(except: kErrorExceptions)
  }

  @Test func testSHC_pedanticZoneChecks() {
    // SHC only checks the points' zone (zp2), never the reference point's
    for (zp2, zp1, zp0, instruction, failure): (UInt8, UInt8, UInt8, HintingInstruction, InterpreterError?) in [
      (0, 0, 0, .SHC_0, nil),
      (0, 0, 0, .SHC_1, nil),
      (0, 0, 1, .SHC_0, nil),
      (0, 0, 1, .SHC_1, nil),
      (0, 1, 0, .SHC_0, nil),
      (0, 1, 0, .SHC_1, nil),
      (0, 1, 1, .SHC_0, nil),
      (0, 1, 1, .SHC_1, nil),
      (1, 0, 0, .SHC_0, .maxpLimitExceeded),
      (1, 0, 0, .SHC_1, .maxpLimitExceeded),
      (1, 0, 1, .SHC_0, .maxpLimitExceeded),
      (1, 0, 1, .SHC_1, .maxpLimitExceeded),
      (1, 1, 0, .SHC_0, .maxpLimitExceeded),
      (1, 1, 0, .SHC_1, .maxpLimitExceeded),
      (1, 1, 1, .SHC_0, .maxpLimitExceeded),
      (1, 1, 1, .SHC_1, .maxpLimitExceeded),
    ] {
      var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 16))
      instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
      instance.run(
        .glyf,
        instructions: [
          .PUSHB([zp2, zp1, zp0]), .SZP0, .SZP1, .SZP2,
          .PUSHB([0]), instruction,
        ],
        failure: failure
      )
      instance.expectedEngineState.variables.zp0 = (zp0 == 0) ? .twilight : .glyph
      instance.expectedEngineState.variables.zp1 = (zp1 == 0) ? .twilight : .glyph
      instance.expectedEngineState.variables.zp2 = (zp2 == 0) ? .twilight : .glyph
      instance.validate(except: [.stack, .twilightPoints])
    }
  }

  // reference interpreter rolls a custom MovePoint for this, same as SHP. it does not barf on integer overflow.
  @Test func testSHC_movePointOverflowDoesNotError() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      hinted: [
        .init(x: .max, y: .min),
        .init(x: 1_000, y: -1_000),
      ],
      scaled: [
        .init(x: 0, y: 0),
        .init(x: 2, y: -4),
      ],
      forZone: .glyph
    )
    instance.setContours([0..<2], forZone: .glyph)

    instance.run(
      .glyf,
      instructions: [
        .setFV(.init(x: .max, y: .max)),
        .pushInt32(0), .SHC_0,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 1].moveTo(
      x: -33_553_432.015625,
      y: 33_553_431.984375,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.variables.freedomVector = .init(x: .max, y: .max)
    instance.validate()
  }

  // MARK: - SHZ 0x36, 0x37
  @Test func testSHZ0_stackUnderflow() {
    runStackUnderflowTests(.glyf, opcode: .SHZ_0, parameters: 1)
  }

  @Test func testSHZ0_wrongZone() {
    runNegativeTest(
      .notGlyf(),
      instructions: .pushInt32(-1),
      .SHZ_0,
      expectingProperties: [.stack([-1])],
      failure: .invalidAccessToGlyphZone
    )
    runNegativeTest(
      .notGlyf(),
      instructions: .pushInt32(2),
      .SHZ_0,
      expectingProperties: [.stack([2])],
      failure: .invalidAccessToGlyphZone
    )

    runNegativeTest(.glyf, instructions: .pushInt32(-1), .SHZ_0, failure: .invalidOperand)
    runNegativeTest(.glyf, instructions: .pushInt32(2), .SHZ_0, failure: .invalidOperand)
  }

  @Test func testSHZ0_missingReferencePoint() {
    runNegativeTest(
      .glyf,
      instructions: [
        .pushInt32(100), .SRP2, .pushInt32(0), .SHZ_0,
      ],
      expectingProperties: [.stack([0]), .variable(\.rp2, 100)],
      failure: .noSuchPoint
    )
  }

  @Test func testSHZ0_contour0Overflow() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 0.5, y: -2), hinted: .init(x: 1.125, y: -3.25)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2, y: -4)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([12..<16], forZone: .glyph)
    instance.run(.glyf, instructions: [.pushInt32(1), .SHZ_0], failure: .invalidOperand)
    instance.validate(except: kErrorExceptions)
  }

  @Test func testSHZ0_sameZone_contourStart0_moveX() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 0.5, y: -2), hinted: .init(x: 1.125, y: -3.25)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2, y: -4)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([0..<4], forZone: .glyph)
    instance.run(.glyf, instructions: [.pushInt32(1), .SHZ_0])
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2.625, y: -4)
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 1.625, y: -5)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 1.625, y: -6)
    instance.validate()
  }

  @Test func testSHZ0_sameZone_contourStart0_refPoint1_moveX() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 1, y: -3), hinted: .init(x: 1, y: -3)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2.125, y: -4.25)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([0..<4], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SRP2,
        .pushInt32(1), .SHZ_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1.125, y: -3)
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 1.125, y: -5)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 1.125, y: -6)
    instance.expectedEngineState.variables.rp2 = 1
    instance.validate()
  }

  @Test func testSHZ0_sameZone_contourStart2_refPoint0_moveX() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 0.5, y: -2), hinted: .init(x: 1.125, y: -3.25)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2, y: -4)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([1..<4], forZone: .glyph)
    instance.run(.glyf, instructions: [.pushInt32(1), .SHZ_0])
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 1.625, y: -5)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 1.625, y: -6)
    instance.validate()
  }

  @Test func testSHZ0_sameZone_contourStart0_refPoint1_moveY() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 1, y: -3), hinted: .init(x: 1, y: -3)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2.125, y: -4.25)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([0..<4], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_Y,
        .pushInt32(1), .SRP2,
        .pushInt32(1), .SHZ_0,
        .SVTCA_X,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1, y: -3.25, yMoved: false)
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 1, y: -5.25, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 1, y: -6.25, yMoved: true)
    instance.expectedEngineState.variables.rp2 = 1
    instance.validate()
  }

  @Test func testSHZ0_sameZone_contourStart2_refPoint0_moveY() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 0.5, y: -2), hinted: .init(x: 1.125, y: -3.25)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2, y: -4)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([1..<4], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_Y,
        .pushInt32(1), .SHZ_0,
        .SVTCA_X,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 1, y: -6.25, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 1, y: -7.25, yMoved: true)
    instance.validate()
  }

  @Test func testSHZ0_sameZone_contourStart0_refPoint1_moveXY() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 1, y: -3), hinted: .init(x: 1, y: -3)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2.125, y: -4.25)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .glyph
    )
    instance.interface.setContours([0..<4], forZone: .glyph)
    let sqrt2 = F2Dot14(Double(2).squareRoot())
    instance.run(
      .glyf,
      instructions: [
        .setPV(.init(x: sqrt2, y: sqrt2)),
        .setFV(.init(x: sqrt2, y: sqrt2)),
        .pushInt32(1), .SRP2,
        .pushInt32(1), .SHZ_0,
        .SVTCA_X,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1.25, y: -2.75, xMoved: true, yMoved: false)
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 1.25, y: -4.75, xMoved: true, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 1.25, y: -5.75, xMoved: true, yMoved: true)
    instance.expectedEngineState.variables.rp2 = 1
    instance.validate()
  }

  @Test func testSHZ0_differentZone_contourStart0_refPoint1_moveXY() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxContours: 2, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(x: 1, y: -3),
        .init(x: 1, y: -4),
        .init(x: 1, y: -5),
        .init(x: 1, y: -6),
      ],
      forZone: .glyph
    )
    instance.setPoints(
      [
        .init(scaled: .init(x: 1, y: -3), hinted: .init(x: 1, y: -3)),
        .init(scaled: .init(x: 2, y: -4), hinted: .init(x: 2.125, y: -4.25)),
        .init(scaled: .init(x: 1, y: -5), hinted: .init(x: 1, y: -5)),
        .init(scaled: .init(x: 1, y: -6), hinted: .init(x: 1, y: -6)),
      ],
      forZone: .twilight
    )
    instance.interface.setContours([0..<4], forZone: .glyph)
    let sqrt2 = F2Dot14(Double(2).squareRoot())
    instance.run(
      .glyf,
      instructions: [
        .setPV(.init(x: sqrt2, y: sqrt2)),
        .setFV(.init(x: sqrt2, y: sqrt2)),
        .pushInt32(1), .SRP2,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SHZ_0,
        .SVTCA_X,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1.25, y: -2.75, xMoved: true, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.25, y: -3.75, xMoved: true, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 1.25, y: -4.75, xMoved: true, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 1.25, y: -5.75, xMoved: true, yMoved: true)
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp2 = 1
    instance.validate()
  }

  @Test func testSHZ0_badZone1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxElements: 1))
    instance.run(
      .glyf,
      instructions: .PUSHB([1]),
      .SHZ_0,
      failure: .invalidOperand
    )
    instance.validate()
  }

  @Test func testSHZ1_badZone1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxElements: 1))
    instance.run(
      .glyf,
      instructions: .PUSHB([1]),
      .SHZ_1,
      failure: .invalidOperand
    )
    instance.validate()
  }

  // The reference implementation of SHZ inlined its own implementation of MovePoint that is less pedantic
  @Test func testSHZ_pedanticZoneChecks() {
    for instruction in [HintingInstruction.SHZ_0, .SHZ_1] {
      var instance = getInstance(maxp: .init(maxPoints: 2))
      instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
      instance.run(
        .glyf,
        instructions: [
          .PUSHB([1]), instruction,
        ]
      )
      instance.validate(except: .points)
    }
  }

  // MARK: - MDAP 0x2e, 0x2f
  @Test func testMDAP_oob() {
    runStackUnderflowTests(opcode: .MDAP_0, parameters: 1)
  }

  @Test func testMDAP_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255]), .MDAP_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].xMoved = true
    instance.expectedEngineState.variables.rp0 = 255
    instance.expectedEngineState.variables.rp1 = 255
    instance.validate()
  }

  @Test func testMDAP_pointmissing() {
    runNegativeTest(.glyf, instructions: [.pushInt32(12), .MDAP_0], failure: .noSuchPoint)
  }

  @Test func testMDAP0_point1() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: 1.25, y: 1.25),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .MDAP_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.25, y: 1.25, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.validate()
  }

  @Test func testMDAP1_point1_nomove() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: 1.25, y: 1.25),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .MDAP_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.25, y: 1.25, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.validate()
  }

  @Test func testMDAP1_point1_nomove_spvtca() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: 1.25, y: 1.25),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SPVTCA_X,
        .pushInt32(1), .MDAP_0,
      ]
    )
    // BUG: see comment in mdap(roundCoordinates:)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.25, y: 1.25, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.validate()
  }

  @Test func testMDAP1_point1_nomove_svtca_x() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: 1.25, y: 1.25),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(1), .MDAP_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.25, y: 1.25, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.validate()
  }

  @Test func testMDAP1_point1_move_x() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: 1.25, y: 1.25),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .MDAP_1,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1, y: 1.25, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.validate()
  }

  @Test func testMDAP1_point1_move_x_freedom() {
    // this sets the projection vector to the Y axis but the freedom vector
    // on the X axis, and as a result moves the point on the X axis by an
    // amount defined by the Y distance
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: 1.25, y: 1.375),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SPVTCA_Y,
        .pushInt32(1), .MDAP_1,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 0.875, y: 1.375, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate()
  }

  @Test func testMDAP1_point1_nomove_svtca_y() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: 1.25, y: 1.25),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_Y,
        .pushInt32(1), .MDAP_1,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.25, y: 1, yMoved: true)
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.freedomVector = FixedVector(x: 0.0, y: 1.0)
    instance.expectedEngineState.variables.projectionVector = FixedVector(x: 0.0, y: 1.0)
    instance.validate()
  }

  @Test func testMDAP1_point1_move_xy() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: 1.55, y: 1.55),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 1]), .SPVTL_0,
        .pushInt32(1), .MDAP_1,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.296875, y: 1.546875, xMoved: true)
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.projectionVector = .init(x: -0.70709228515625, y: -0.70709228515625)
    instance.validate()
  }

  @Test func testMDAP_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .zero,
        .init(x: .max, y: .max),
      ],
      forZone: .glyph
    )

    instance.run(
      .glyf,
      instructions: [
        .PUSHW([F2Dot14.max.bitPattern, F2Dot14.max.bitPattern]), .SPVFS,
        .PUSHB([1]), .MDAP_1,
      ],
      failure: .arithmeticError
    )
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.projectionVector = .init(x: F2Dot14.max, y: F2Dot14.max)

    instance.validate(except: [.glyphPoints])
  }

  @Test func testMDAP0_pedanticZoneChecks() {
    for instruction in [HintingInstruction.MDAP_0, .MDAP_1] {
      runNegativeTest(
        .glyf,
        glyphPoints: Array(repeating: .zero, count: 16),
        instructions: [.pushInt32(1), instruction],
        failure: .maxpLimitExceeded
      )
    }
  }

  // MARK: - SHPIX 0x38
  @Test func testSHPIX_noop() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints([.init(x: 1.125, y: -3.25)], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(0), .SLOOP,
        .pushF26Dot6(10_000), .SHPIX,
      ]
    )
    instance.validate()
  }

  @Test func testSHPIX_xMoved_zero_delta() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 0]), .SHPIX,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].xMoved = true
    instance.validate()
  }

  @Test func testSHPIX_yMoved_zero_delta() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .SFVTCA_Y, .PUSHB([0, 0]), .SHPIX,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].yMoved = true
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.validate()
  }

  @Test func testSHPIX_missing_point() {
    runNegativeTest(
      .glyf,
      instructions: [.PUSHB([100, 100, 7]), .SLOOP, .SHPIX],
      expectingProperties: [.variable(\.loop, 7)],
      failure: .noSuchPoint
    )
  }

  @Test func testSHPIX_stack_underflow() {
    // no operand for projection
    runNegativeTest(
      .glyf,
      instructions: [.pushInt32(3), .SLOOP, .SHPIX],
      expectingProperties: [.variable(\.loop, 3)],
      failure: .stackUnderflow
    )

    // no operand for to-be-moved point
    runNegativeTest(
      .glyf,
      instructions: [.PUSHB([100, 4]), .SLOOP, .SHPIX],
      expectingProperties: [.variable(\.loop, 4)],
      failure: .stackUnderflow
    )
  }

  @Test func testSHPIX_overflow() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: .init(bitPattern: .max), y: .init(bitPattern: .max)), at: 0, in: .glyph),
        .pushInt32(0), .pushF26Dot6(1_000), .SHPIX,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(
      x: -33_553_432.015625,
      y: 33_554_431.984375,
      xMoved: true,
      yMoved: true
    )
    instance.validate()
  }

  @Test func testSHPIX_two_points() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25), .init(x: 2.5, y: 5),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2), .SLOOP,
        .pushInt32(0), .pushInt32(1), .pushF26Dot6(1_000), .SHPIX,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1_001.125, y: -3.25, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1_002.5, y: 5, xMoved: true)
    instance.validate()
  }

  @Test func testSHPIX_misalignedVectors() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let freedomVector = FixedVector<F2Dot14>.normalizing(x: 0.2, y: 0.3)
    instance.run(
      .glyf,
      instructions: [
        .NPUSHW([freedomVector.x.bitPattern, freedomVector.y.bitPattern]), .SFVFS,
        .pushInt32(0), .pushF26Dot6(1_000), .SHPIX,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 554.75, y: 832.09375, xMoved: true, yMoved: true)
    instance.expectedEngineState.variables.freedomVector = freedomVector
    instance.validate()
  }

  @Test func testSHPIX_same_point_multiple_times() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25), .init(x: 2.5, y: 5),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2), .SLOOP,
        .pushInt32(0), .pushInt32(0), .pushF26Dot6(1_000), .SHPIX,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 2_001.125, y: -3.25, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2.5, y: 5)
    instance.validate()
  }

  // The reference implementation of SHPIX is not pedantic about its zone
  @Test func testSHPIX_pedanticZoneChecks() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 0]), .SHPIX,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].xMoved = true
    instance.validate()
  }

  // MARK: - IP 0x39
  @Test func testIP_twilight_1point_noop() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints([.init(x: 2, y: 1), .init(x: 4, y: 2)], forZone: .glyph)
    instance.setPoints([.init(x: 1, y: -3), .init(x: 2, y: -6)], forZone: .twilight)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(0), .SZP2,
        .pushInt32(1), .SLOOP,
        .pushInt32(1), .IP,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.twilightPoints[point: 1].xMoved = true
    instance.validate()
  }

  @Test func testIP_twilight_2points_noop() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints([.init(x: 2, y: 1), .init(x: 2, y: 3)], forZone: .glyph)
    instance.setPoints([.init(x: 1, y: -3), .init(x: 2, y: -6)], forZone: .twilight)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(0), .SZP2,
        .pushInt32(2), .SLOOP,
        .pushInt32(0), .pushInt32(1), .IP,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.twilightPoints[point: 0].xMoved = true
    instance.expectedEngineState.twilightPoints[point: 1].xMoved = true
    instance.validate()
  }

  @Test func testIP_twilight_1point_oldrangeZ_move() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints([.init(x: 1.125, y: -3.25), .init(x: 2, y: -6)], forZone: .twilight)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(0), .SZP2,
        .pushInt32(0), .pushInt32(1), .ALIGNPTS,
        .pushInt32(1), .SLOOP,
        .pushInt32(1), .IP,
      ]
    )
    instance.expectedEngineState.twilightPoints[point: 0].moveTo(x: 1.5625, y: -3.25, xMoved: true)
    instance.expectedEngineState.twilightPoints[point: 1].moveTo(x: 2.4375, y: -6, xMoved: true)
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }

  @Test func testIP_twilight_1point_oldrangeNZ_move() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 4))
    instance.setPoints([.init(x: 1.125, y: -3.25), .init(x: 0.5, y: 1), .init(x: 2, y: -6)], forZone: .twilight)
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(0), .SZP2,
        .pushInt32(0), .SRP1,
        .pushInt32(1), .SRP2,
        .pushInt32(0), .pushInt32(1), .ALIGNPTS,
        .pushInt32(1), .SLOOP,
        .pushInt32(2), .IP,
      ]
    )
    instance.expectedEngineState.twilightPoints[point: 0].moveTo(x: 0.8125, y: -3.25, xMoved: true)
    instance.expectedEngineState.twilightPoints[point: 1].moveTo(x: 0.8125, y: 1, xMoved: true)
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 0.8125, y: -6, xMoved: true)
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.variables.rp2 = 1
    instance.validate()
  }

  @Test func testIP_glyph_1point_oldrangeZ_move() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.setPoints(
      scaled: [
        .init(x: 1.125, y: -3.25),
        .init(x: 2, y: -6),
      ],
      original: [
        .init(x: 1, y: -3),
        .init(x: 2, y: -6),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .SZP2,
        .pushInt32(0), .pushInt32(1), .ALIGNPTS,
        .pushInt32(1), .SLOOP,
        .pushInt32(1), .IP,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1.5625, y: -3.25, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.578125, y: -6, xMoved: true)
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.zp2 = .glyph
    instance.validate()
  }

  @Test func testIP_glyph_1point_oldrangeNZ_move() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25), .init(x: 0.5, y: 1), .init(x: 2, y: -6),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .SZP2,
        .pushInt32(0), .SRP1,
        .pushInt32(1), .SRP2,
        .pushInt32(0), .pushInt32(1), .ALIGNPTS,
        .pushInt32(1), .SLOOP,
        .pushInt32(2), .IP,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 0.8125, y: -3.25, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 0.8125, y: 1, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 0.8125, y: -6, xMoved: true)
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.zp2 = .glyph
    instance.expectedEngineState.variables.rp2 = 1
    instance.validate()
  }

  @Test func testIP_stack_underflow() {
    runNegativeTest(
      .glyf,
      instructions: [
        .setPoint(.init(x: 2, y: 1), at: 0, in: .glyph),
        .setPoint(.init(x: 1, y: -3), at: 0, in: .twilight),
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(0), .SZP2,
        .pushInt32(1), .SLOOP,
        .IP,
      ],
      expectingProperties: [
        .variable(\.zp0, .twilight),
        .variable(\.zp1, .twilight),
        .variable(\.zp2, .twilight),
      ],
      exemptingProperties: .points,
      failure: .stackUnderflow
    )
  }

  @Test func testIP_zeroLoop() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    let instructions: [HintingInstruction] = [
      .setPoint(.init(x: 2, y: 1), at: 0, in: .glyph),
      .setPoint(.init(x: 1, y: -3), at: 0, in: .twilight),
      .pushInt32(0), .SLOOP,
      .IP,
    ]

    instance.run(.glyf, instructions: instructions)
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 2, y: 1, xMoved: true, yMoved: true)
    instance.expectedEngineState.twilightPoints[point: 0] = .init(x: 1, y: -3, xMoved: true, yMoved: true)
    instance.validate()
  }

  @Test func testIP_unscaledOutlineIsWrong() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(scaled: .init(x: 1, y: -3), hinted: .init(x: 1.125, y: -3.25)),
        .init(scaled: .init(x: 0, y: 1), hinted: .init(x: 0.5, y: 1)),
        .init(scaled: .init(x: 2.5, y: -6.5), hinted: .init(x: 2, y: -6)),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(1), .SZPS,
        .pushInt32(0), .SRP1,
        .pushInt32(1), .SRP2,
        .pushInt32(0), .pushInt32(1), .ALIGNPTS,
        .pushInt32(1), .SLOOP,
        .pushInt32(2), .IP,
      ],
      unscaledOutlineIsWrong: true
    )
    instance.expectedEngineState.glyphPoints[point: 0] = OutlinePoint(
      original: .init(x: 3, y: -13),
      scaled: .init(x: 1.0, y: -3.0),
      hinted: .init(x: 0.8125, y: -3.25),
      xMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 1] = OutlinePoint(
      original: .init(x: 3, y: 4),
      scaled: .init(x: 0.0, y: 1.0),
      hinted: .init(x: 0.8125, y: 1.0),
      xMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 2] = OutlinePoint(
      original: .init(x: 8, y: -24),
      scaled: .init(x: 2.5, y: -6.5),
      hinted: .init(x: 0.890625, y: -6.0),
      xMoved: true
    )
    instance.expectedEngineState.variables.rp2 = 1
    instance.validate()
  }

  @Test func testIP_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255]), .IP,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].xMoved = true
    instance.validate()
  }

  @Test func testIP_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 4, maxTwilightPoints: 4))
    instance.setPoints(
      [
        .init(x: .max, y: .max),
        .init(x: 0.5, y: 1),
        .init(x: .min, y: .min),
      ],
      forZone: .glyph
    )

    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .SZP2,
        .pushInt32(0), .SRP1,
        .pushInt32(1), .SRP2,
        .pushInt32(1), .SLOOP,
        .pushInt32(2), .IP,
      ],
      failure: .arithmeticError
    )

    instance.validate(except: [.glyphPoints, .referencePoints])
  }

  @Test func testIP_pedanticZoneChecks() {
    runNegativeTest(
      .glyf,
      glyphPoints: Array(repeating: .zero, count: 16),
      instructions: [.PUSHB([0]), .IP],
      failure: .maxpLimitExceeded
    )
  }

  // Aliasing case: the popped point is the same as rp1 (the reference point captured
  // into ref1Hinted before the loop). When pt aliases ref1: `pt.hinted - ref1Hinted` = 0
  // (the snapshot was taken at the same memory address pt now reads from), and
  // `newCoord - dualRefPoint` = 0 (same reasoning for the unscaled side). Both
  // projections collapse to 0; movePoint receives delta 0; rp1 doesn't move.
  // This test proves the snapshot of ref1Hinted is equivalent to live reads here.
  @Test func testIP_aliasRP1() {
    var instance = getInstance(maxp: .init(maxPoints: 3))
    instance.setPoints(
      [.init(x: 1.125, y: -3.25), .init(x: 0.5, y: 1), .init(x: 2, y: -6)],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SRP1,
        .pushInt32(2), .SRP2,
        .pushInt32(1), .SLOOP,
        .pushInt32(0), .IP,  // pop = 0 == rp1; should be no-op move
      ]
    )
    // Points 0 and 2 unchanged in coordinates; point 0 picks up touched flag
    // (movePoint sets xMoved unconditionally for the projected axis).
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 1.125, y: -3.25, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1] = .init(x: 0.5, y: 1)
    instance.expectedEngineState.glyphPoints[point: 2] = .init(x: 2, y: -6)
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 2
    instance.validate()
  }

  // Cross-iteration aliasing for IP: first pop a non-rp point (real interpolation),
  // then pop rp1 (alias, should be no-op). The second iteration's snapshot of
  // ref1Hinted must still yield the correct delta — and since the first iteration
  // didn't modify rp1's memory, snapshot equals live read.
  @Test func testIP_aliasRP1_afterMove() {
    var instance = getInstance(maxp: .init(maxPoints: 4))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25),
        .init(x: 0.5, y: 1),
        .init(x: 2, y: -6),
        .init(x: 3, y: 0),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SRP1,
        .pushInt32(2), .SRP2,
        .pushInt32(0), .pushInt32(1), .ALIGNPTS,  // move rp1 (point 0) to align with point 1, making oldRange non-zero
        .pushInt32(2), .SLOOP,
        .PUSHB([0, 3]),  // pop 3 first (real interp), then 0 (alias rp1)
        .IP,
      ]
    )
    // After ALIGNPTS: p0 and p1 both at x=0.8125 (avg of 1.125 and 0.5)
    // Then IP with loop=2:
    //   Iter 1 (pop 3): real interpolation of point 3 between rp1 (0) and rp2 (2)
    //   Iter 2 (pop 0): alias rp1; should be a no-op move (delta 0)
    // Point 3 lands at x=0.8125 (specific interpolated value — see testIP_aliasRP1_beforeMove for
    // the order-independence check that this value matches when iteration order is swapped).
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 0.8125, y: -3.25, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 0.8125, y: 1, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 2] = .init(x: 2, y: -6)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 0.8125, y: 0, xMoved: true)
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 2
    instance.validate()
  }

  // Aliasing rp1 *before* a real interpolation. The first iteration must not
  // disturb rp1's coordinates, so the second iteration's interpolation reads
  // rp1's original-positioned hinted value (whether via snapshot or live).
  // If snapshot and live diverge here, this test would produce a different x
  // for point 3 than testIP_aliasRP1_afterMove. Identical results prove
  // order-independence and therefore aliasing-safety.
  @Test func testIP_aliasRP1_beforeMove() {
    var instance = getInstance(maxp: .init(maxPoints: 4))
    instance.setPoints(
      [
        .init(x: 1.125, y: -3.25),
        .init(x: 0.5, y: 1),
        .init(x: 2, y: -6),
        .init(x: 3, y: 0),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SRP1,
        .pushInt32(2), .SRP2,
        .pushInt32(0), .pushInt32(1), .ALIGNPTS,
        .pushInt32(2), .SLOOP,
        .PUSHB([3, 0]),  // pop 0 first (alias rp1), then 3 (real interp)
        .IP,
      ]
    )
    // Same final positions as testIP_aliasRP1_afterMove — by design, to prove
    // order-independence and therefore no aliasing-induced divergence.
    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 0.8125, y: -3.25, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 0.8125, y: 1, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 2] = .init(x: 2, y: -6)
    instance.expectedEngineState.glyphPoints[point: 3].moveTo(x: 0.8125, y: 0, xMoved: true)
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 2
    instance.validate()
  }

  // MARK: - MSIRP 0x3a-0x3b
  /*
   Makes it possible to coordinate the distance between a point and a reference point by setting
   the distance from a value popped from the stack.

   Pops a distance, d and a point number, p, and makes the distance between point p and the
   current position of rp0 equal to d. The distance, d, is in pixel coordinates.

   MSIRP[ ] is very similar to the MIRP[ ] instruction except for taking the distance from the
   stack rather than the CVT. Since MSIRP[ ] does not use the CVT, the control value cut-in is
   not a factor as it is in MIRP[ ]. Since MSIRP[ ] does not round, its effect is not dependent
   upon the round state.

   MSIRP[] can be used to create points in the twilight zone.

   In the illustration below, point p is moved along the freedom vector until it is at a distance
   d from rp0.
   */

  @Test func testMSIRP_stackUnderflow() {
    runStackUnderflowTests(opcode: .MSIRP(setRP0: false), parameters: 2)
  }

  @Test func testMSIRP_missingPointToModify() {
    runNegativeTest(
      .glyf,
      instructions: [
        .pushInt32(100),
        .pushF26Dot6(123),
        .MSIRP(setRP0: false),
      ],
      failure: .noSuchPoint
    )
  }

  @Test func testMSIRP_missingReferencePoint() {
    runNegativeTest(
      .glyf,
      glyphPoints: [
        OutlinePoint(x: 1, y: 1)
      ],
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(100), .SRP0,
        .pushInt32(1), .pushF26Dot6(123), .MSIRP(setRP0: false),
      ],
      expectingProperties: [
        .variable(\.rp0, 100),
        .variable(\.zp0, .glyph),
      ],
      failure: .noSuchPoint
    )
  }

  @Test func testMSIRP_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255, 255]), .MSIRP(setRP0: false),
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].move(to: .init(x: 3.984375, y: 0.0), xMoved: true)
    instance.expectedEngineState.variables.rp2 = 255
    instance.validate()
  }

  @Test func testMSIRP_glyphZone_noReset_normalDistance() {
    var instance = getInstance(maxp: .init(maxPoints: 3))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: 2.75, y: 2.75),
        OutlinePoint(x: 4.75, y: 4.75),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SRP0,
        .pushInt32(2), .pushF26Dot6(10), .MSIRP(setRP0: false),
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 12.75, y: 4.75, xMoved: true)
    instance.validate()
  }

  @Test func testMSIRP_glyphZone_reset_normalDistance() {
    var instance = getInstance(maxp: .init(maxPoints: 3))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: 2.75, y: 2.75),
        OutlinePoint(x: 4.75, y: 4.75),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SRP0,
        .pushInt32(2), .pushF26Dot6(10), .MSIRP(setRP0: true),
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.rp0 = 2
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 12.75, y: 4.75, xMoved: true)
    instance.validate()
  }

  @Test func testMSIRP_glyphZone_noReset_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 3))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: 2.75, y: 2.75),
        OutlinePoint(x: 4.75, y: 4.75),
      ],
      forZone: .glyph
    )

    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SRP0,
        .pushInt32(2), .pushF26Dot6(.min), .MSIRP(setRP0: false),
      ],
      failure: .arithmeticError
    )

    // moving the point happens fairly deep into the opcode, but all of this will be reset anyway.
    instance.validate(except: [.stack, .referencePoints, .glyphPoints])
  }

  @Test func testMSIRP_twilightZone() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      [
        OutlinePoint(x: 0.5, y: 1.5),
        OutlinePoint(x: 2.5, y: 4),
        OutlinePoint(x: 6, y: 8),
      ],
      forZone: .glyph
    )
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: 2.75, y: 2.75),
        OutlinePoint(x: 4.75, y: 4.75),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .setFV(.init(x: 0.75, y: 0.75)),
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,
        .pushInt32(2), .pushF26Dot6(10), .MSIRP(setRP0: true),
      ]
    )
    instance.expectedEngineState.variables.freedomVector = .init(x: 0.75, y: 0.75)
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 2
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].scaled = .init(x: 12.5, y: 4.0)
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 12.5, y: 14, xMoved: true, yMoved: true)
    instance.validate()
  }

  // zp1 is checked
  @Test func testMSIRP_pedanticZoneChecks1() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 16))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0]), .SZP0,
        .PUSHB([0, 0]), .MSIRP(setRP0: false),
      ],
      failure: .maxpLimitExceeded
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.validate()
  }

  // zp0 is not checked
  @Test func testMSIRP_pedanticZoneChecks2() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 16))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0]), .SZP1,
        .PUSHB([0, 0]), .MSIRP(setRP0: false),
      ]
    )
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.twilightPoints[point: 0].xMoved = true
    instance.validate()
  }

  // MARK: - ALIGNRP 0x3c
  /*
   Create an axis passing through rp0 that is orthogonal to the projection vector. Pop `gs.loop`
   points from the stack and align each of those to that axis.
   */
  @Test func testALIGNRP_X_1() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let p0 = OutlinePoint(x: 0, y: 1)
    let p1 = OutlinePoint(x: 2, y: -1)
    instance.setPoints([p0, p1], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1),
        .SLOOP,
        .SVTCA_X,
        .PUSHB([1]),
        .ALIGNRP,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0] = p0
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 0, y: -1, xMoved: true)
    instance.validate()
  }

  func testALIGNRP_Y_1() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let p0 = OutlinePoint(x: 0, y: 1)
    let p1 = OutlinePoint(x: 2, y: -1)
    instance.setPoints([p0, p1], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1),
        .SLOOP,
        .SVTCA_Y,
        .PUSHB([1]),
        .ALIGNRP,
        .SVTCA_X,  // Reset vectors to default values
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0] = p0
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2, y: 1, yMoved: true)
    instance.validate()
  }
  @Test func testALIGNRP_2() {
    var instance = getInstance(maxp: .init(maxPoints: 3))
    let p0 = OutlinePoint(x: 0, y: 1)
    let p1 = OutlinePoint(x: 2, y: -1)
    let p2 = OutlinePoint(x: 2.5, y: 0.5)
    instance.setPoints([p0, p1, p2], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2),
        .SLOOP,
        .SVTCA_X,
        .PUSHB([2, 1]),
        .ALIGNRP,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0] = p0
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 0, y: -1, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 0, y: 0.5, xMoved: true)
    instance.validate()
  }

  @Test func testALIGNRP_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 2))

    instance.run(
      .glyf,
      instructions: [
        .setPoint(.init(x: .min, y: .max), at: 0, in: .glyph),
        .setPoint(.init(x: .max, y: .min), at: 1, in: .glyph),
        .SVTCA_X,
        .pushInt32(1),
        .SLOOP,
        .PUSHB([1]),
        .ALIGNRP,
      ],
      failure: .arithmeticError
    )

    instance.validate(except: [.points])
  }

  @Test func testALIGNRP_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255]), .ALIGNRP,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].xMoved = true
    instance.validate()
  }

  @Test func testALIGNRP_OOB() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2), .SLOOP,
        .pushInt32(99), .pushInt32(0), .ALIGNRP,
      ],
      failure: .noSuchPoint
    )
    instance.expectedEngineState.variables.loop = 1
    instance.expectedEngineState.stack = []
    instance.expectedEngineState.glyphPoints.points[0].xMoved = true
    instance.validate()
  }

  // There are two ways to do OOB! The reference point and the points in the range.
  @Test func testALIGNRP_OOB2() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2), .SLOOP,
        .pushInt32(0), .pushInt32(99), .ALIGNRP,
      ],
      failure: .noSuchPoint
    )
    instance.expectedEngineState.variables.loop = 2
    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testALIGNRP_tooFewStackElements() {
    runNegativeTest(
      .glyf,
      instructions: [.pushInt32(1), .SLOOP, .ALIGNRP],
      expectingProperties: [.variable(\.loop, 1)],
      failure: .stackUnderflow
    )

    runNegativeTest(
      .glyf,
      instructions: [.pushInt32(2), .SLOOP, .ALIGNRP],
      expectingProperties: [.variable(\.loop, 2)],
      failure: .stackUnderflow
    )

    var instance = getInstance(maxp: .init(maxPoints: 1))
    instance.setPoints([OutlinePoint(x: 0, y: 0)], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2),
        .SLOOP,
        .PUSHB([0]),
        .ALIGNRP,
      ],
      failure: .stackUnderflow
    )
    instance.expectedEngineState.variables.loop = 1
    instance.expectedEngineState.glyphPoints[point: 0] = OutlinePoint(x: 0, y: 0, xMoved: true)
    instance.validate()
  }

  @Test func testALIGNRP_pedanticZoneChecks1() {
    runNegativeTest(
      .glyf,
      glyphPoints: Array(repeating: .zero, count: 16),
      instructions: [.PUSHB([0]), .ALIGNRP],
      failure: .maxpLimitExceeded
    )
  }

  // Aliasing case: zp0 == zp1 (both default to glyph) and the popped index equals rp0.
  // The reference point IS the working point. Algebraically, `p.hinted - p0` = 0, so
  // movePoint receives delta 0; coordinates stay put, only the touched flags are set.
  // This test exists to prove the snapshot-vs-live-read distinction doesn't matter here.
  @Test func testALIGNRP_selfAlias() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let p0 = OutlinePoint(x: 3, y: 5)
    let p1 = OutlinePoint(x: 7, y: -2)
    instance.setPoints([p0, p1], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1),
        .SLOOP,
        .SVTCA_X,
        .PUSHB([0]),  // align point 0 (== rp0) with rp0
        .ALIGNRP,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 3, y: 5, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1] = p1
    instance.validate()
  }

  // Cross-iteration aliasing: pop rp0 first (no-op move), then pop a different point.
  // If the snapshot of p0 were stale after iteration 1, iteration 2's delta would be
  // wrong. But iteration 1's delta is 0 (self-align), so rp0 doesn't actually move.
  @Test func testALIGNRP_aliasFirstThenOther() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let p0 = OutlinePoint(x: 3, y: 5)
    let p1 = OutlinePoint(x: 7, y: -2)
    instance.setPoints([p0, p1], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2),
        .SLOOP,
        .SVTCA_X,
        .PUSHB([1, 0]),  // stack pops 0 first, then 1
        .ALIGNRP,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 3, y: 5, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 3, y: -2, xMoved: true)
    instance.validate()
  }

  // Same as above but reversed: move the other point first (non-alias), then attempt
  // to "align" rp0 with itself (alias). The second iteration's snapshot must still
  // produce delta 0 — and crucially, p0's coordinates must not have been disturbed
  // by the first iteration (different point in different memory).
  @Test func testALIGNRP_otherThenAlias() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let p0 = OutlinePoint(x: 3, y: 5)
    let p1 = OutlinePoint(x: 7, y: -2)
    instance.setPoints([p0, p1], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2),
        .SLOOP,
        .SVTCA_X,
        .PUSHB([0, 1]),  // pop 1 first (moves p1), then pop 0 (self-align rp0)
        .ALIGNRP,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 3, y: 5, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 3, y: -2, xMoved: true)
    instance.validate()
  }

  // Repeated alias: pop rp0 twice in a row. Both iterations should be no-op moves;
  // rp0's coordinates must be preserved even though the touched flags accumulate.
  @Test func testALIGNRP_repeatedAlias() {
    var instance = getInstance(maxp: .init(maxPoints: 1))
    let p0 = OutlinePoint(x: 3, y: 5)
    instance.setPoints([p0], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(2),
        .SLOOP,
        .SVTCA_X,
        .PUSHB([0, 0]),
        .ALIGNRP,
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: 3, y: 5, xMoved: true)
    instance.validate()
  }

  // MARK: - RTDG 0x3d
  @Test func testRTDG_state() {
    var instance = getInstance()
    instance.run(instructions: .setRoundState(.rtdg))
    instance.expectedEngineState.variables.roundState = .rtdg
    instance.validate()
  }

  @Test func testRTDG_rounding() {
    runRoundingTest(roundingMode: .rtdg) { value in
      if let rounded = F27Dot5(bitPattern: value.bitPattern).roundingIfRepresentable() {
        return F26Dot6(bitPattern: rounded.bitPattern)
      }
      return 0
    }
  }

  // MARK: - MIAP 0x3E, 0x3F
  @Test func testMIAP_stackunderflow() {
    runStackUnderflowTests(opcode: .MIAP_0, parameters: 2)
  }

  @Test func testMIAP_missingControlValue() {
    runNegativeTest(
      .glyf,
      instructions: [.pushInt32(0), .pushInt32(2_000), .MIAP_0],
      expectingProperties: [.stack([0])],
      failure: .cvtLocationOutOfBounds
    )
  }

  // bincompat: in fpgm cpp will "read" zeroes from cvt in the context of MIAP (it swallows the index and returns 0),
  // then later it will fail for not having any zones. ideally STTI
  // would succeed at "reading" CVT and fail because of the glyph zone,
  // but that's academic.
  @Test func testMIAP_missingControlValue_fpgm() {
    runNegativeTest(
      .fpgm,
      instructions: .pushInt32(0),
      .pushInt32(2_000),
      .MIAP_0,
      failure: .cvtLocationOutOfBounds
    )
  }

  @Test func testMIAP_missingPoint() {
    runNegativeTest(
      .glyf,
      fUnitControlValues: [2],
      instructions: [.pushInt32(10), .pushInt32(0), .MIAP_0],
      failure: .noSuchPoint
    )
  }

  @Test func testMIAP_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max), cvtCount: 256)
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255, 255]), .MIAP_0,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].xMoved = true
    instance.expectedEngineState.variables.rp0 = 255
    instance.expectedEngineState.variables.rp1 = 255
    instance.validate()
  }

  @Test func testMIAP_glyph_noround() {
    var instance = getInstance(maxp: .init(maxPoints: 2), cvtCount: 1)
    instance.setCVT([3.5])
    instance.setPoints(
      [
        OutlinePoint(x: -1.5, y: -2.5),
        OutlinePoint(x: 1.5, y: 2.5),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1),  // point index
        .pushInt32(0),  // CVT entry
        .MIAP_0,
      ]
    )
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 3.5, y: 2.5, xMoved: true)
    instance.validate()
  }

  @Test func testMIAP_glyph_round_cvtmin() {
    var instance = getInstance(maxp: .init(maxPoints: 2), cvtCount: 1)
    instance.setCVT([.min])
    instance.setPoints(
      [
        OutlinePoint(x: -1.5, y: -2.5),
        OutlinePoint(x: 0, y: 2.5),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1),  // point index
        .pushInt32(0),  // CVT entry
        .MIAP_1,
      ]
    )
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: .min, y: 2.5, xMoved: true)
    instance.validate()
  }

  @Test func testMIAP_glyph_round_noCutIn() {
    var instance = getInstance(maxp: .init(maxPoints: 2), cvtCount: 1)
    instance.setCVT([4.5])
    instance.setPoints(
      [
        OutlinePoint(x: -1.5, y: -2.5),
        OutlinePoint(x: 0, y: 2.5),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushF26Dot6(10), .SCVTCI,
        .pushInt32(1),  // point index
        .pushInt32(0),  // CVT entry
        .MIAP_1,
      ]
    )
    instance.expectedEngineState.variables.controlValueCutIn = 10
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 5, y: 2.5, xMoved: true)
    instance.validate()
  }

  @Test func testMIAP_glyph_round_cutIn() {
    var instance = getInstance(maxp: .init(maxPoints: 2), cvtCount: 1)
    instance.setCVT([4.5])
    instance.setPoints(
      [
        OutlinePoint(x: -1.5, y: -2.5),
        OutlinePoint(x: 2.5, y: 2.5),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushF26Dot6(1), .SCVTCI,
        .pushInt32(1),  // point index
        .pushInt32(0),  // CVT entry
        .MIAP_1,
      ]
    )
    instance.expectedEngineState.variables.controlValueCutIn = 1
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 3, y: 2.5, xMoved: true)
    instance.validate()
  }

  @Test func testMIAP_twilight_cutIn() {
    var instance = getInstance(maxp: .init(maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([4.5])
    instance.setPoints(
      [
        OutlinePoint(x: -1.5, y: -2.5),
        OutlinePoint(x: 2.5, y: 2.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(0), .SZP0,
        .pushF26Dot6(1), .SCVTCI,
        .pushInt32(1),  // point index
        .pushInt32(0),  // CVT entry
        .MIAP_1,
      ]
    )

    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.controlValueCutIn = 1
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.twilightPoints[point: 1] = OutlinePoint(
      scaled: .init(x: 4.5, y: 0.0),
      hinted: .init(x: 5, y: 0),
      xMoved: true
    )
    instance.validate()
  }

  @Test func testMIAP_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 2), cvtCount: 1)
    instance.setCVT([.min])
    instance.setPoints(
      [
        OutlinePoint(x: .min, y: .max)
      ],
      forZone: .glyph
    )

    instance.run(
      .glyf,
      instructions: [
        .pushInt32(0),  // point index
        .pushInt32(0),  // CVT entry
        .PUSHW([F2Dot14.max.bitPattern, F2Dot14.max.bitPattern]), .SPVFS,
        .PUSHW([F2Dot14.max.bitPattern, F2Dot14.max.bitPattern]), .SFVFS,
        .MIAP_1,
      ],
      failure: .arithmeticError
    )

    instance.expectedEngineState.variables.freedomVector = .init(x: .max, y: .max)
    instance.expectedEngineState.variables.projectionVector = .init(x: .max, y: .max)
    instance.validate(except: [.glyphPoints])
  }

  @Test func testMIAP_pedanticZoneChecks() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(.glyf, instructions: [.PUSHB([0, 0]), .MIAP_1], failure: .maxpLimitExceeded)
    instance.validate()
  }

  // MARK: - NPUSHB 0x41
  /*
   Takes n bytes from the instruction stream and pushes them onto the stack.

   Looks at the next byte in the instructions stream, n, and takes n unsigned bytes from the
   instruction stream, where n is an unsigned integer in the range (0 255), and pushes them onto
   the stack. The number of bytes to push, n, is not pushed onto the stack.

   Each byte value is unsigned extended to 32 bits before being pushed onto the stack.
   */

  @Test func testNPUSHB() {
    let byte: UInt8 = 0x83

    var instance = getInstance()
    instance.run(instructions: .NPUSHB([byte]))

    instance.expectedEngineState.stack.append(Int32(byte))
    instance.validate()
  }

  @Test func testNPUSHB_zeroBytes() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([]))
    instance.validate()
  }

  @Test func testNPUSHB_255Bytes() {
    var bytes = [UInt8]()
    for idx: UInt8 in 0..<255 { bytes.append(idx) }
    var instance = getInstance()
    instance.run(instructions: .NPUSHB(bytes))

    for idx in 0..<255 {
      instance.expectedEngineState.stack.append(Int32(254 - idx))
    }
    instance.validate()
  }

  @Test func testNPUSHB_insufficientBytes() {
    runNegativeTest(instructions: .literal(HintingInstruction.NPUSHB([]).opcode), failure: .ranOffEndOfInstructions)
    for numBytes in 1...UInt8.max {
      runNegativeTest(
        instructions: .NPUSHB(Array(repeating: 0xaa, count: Int(numBytes) - 1), n: numBytes),
        failure: .ranOffEndOfInstructions
      )
    }
  }

  // MARK: - NPUSHW 0x41
  /*
   Takes n words from the instruction stream and pushes them onto the stack.

   Looks at the next instruction stream byte n and takes n 16-bit signed words from the
   instruction stream, where n is an unsigned integer in the range (0 255), and pushes them onto
   the stack. Each word is sign extended to 32 bits before being placed on the stack.The value n
   is not pushed onto the stack.
   */

  @Test func testNPUSHW() {
    let word: Int16 = 0x34ab
    var instance = getInstance()
    instance.run(instructions: .NPUSHW([word]))

    instance.expectedEngineState.stack.append(0x34ab)
    instance.validate()
  }

  @Test func testNPUSHW_zeroWords() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHW([]))
    instance.validate()
  }

  @Test func testNPUSHW_255Words() {
    var words = [Int16]()
    for idx: Int16 in 0..<255 { words.append((0x74 << 8) + idx) }
    var instance = getInstance()
    instance.run(instructions: .NPUSHW(words))

    for idx in 0..<255 {
      instance.expectedEngineState.stack.append(Int32((0x74 << 8) + 254 - idx))
    }
    instance.validate()
  }

  @Test func testNPUSHW_signExtendNegative() {
    let word: Int16 = -801
    var instance = getInstance()
    instance.run(instructions: .NPUSHW([word]))

    instance.expectedEngineState.stack.append(Int32(word))
    instance.validate()
  }

  @Test func testNPUSHW_insufficientWords() {
    runNegativeTest(instructions: .literal(HintingInstruction.NPUSHW([]).opcode), failure: .ranOffEndOfInstructions)
    for numBytes in 1...UInt8.max {
      runNegativeTest(
        instructions: .NPUSHW(Array(repeating: 0x4aaa, count: Int(numBytes) - 1), n: numBytes),
        failure: .ranOffEndOfInstructions
      )
    }
  }

  // go super hard on overflowing so that even the cpp interpreter will balk
  @Test func testNPUSHW_stackOverflow_max() {
#if !os(watchOS)
    let maxStackElements: UInt16 = .max
    var instance = getInstance(maxp: .init(maxStackElements: maxStackElements))

    // NPUSHW + count + 255 pairs of bytes -> need to jump -512 to get to pc = 0
    let jumpDistance = -512
    instance.run(
      instructions: [.NPUSHW(.init(repeating: Int16(jumpDistance), count: 255)), .JMPR],
      failure: .stackDepthExceedsLimit
    )

    instance.expectedEngineState.stack = .init(repeating: Int32(jumpDistance), count: Int(maxStackElements))
    instance.validate()
#endif
  }

  // MARK: - WS 0x42
  // Note: this is from Apple's documentation and is wrong. first it pops the value, then the location.
  /*
   Pops a storage area location l, followed by a value, v. Writes this 32-bit value into the
   storage area location indexed by l. The value must be less than the number of storage
   locations specified in the 'maxp' table of the font file.
   */

  @Test func testWS() {
    let location: Int32 = 0x01
    let value: Int32 = 0x4536_2718
    var instance = getInstance()
    instance.run(instructions: .pushInt32(location), .pushInt32(value), .WS)

    instance.expectedEngineState.storage[Int(location)] = value
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testWS_indexOutOfBounds() {
    var instance = getInstance(maxp: .init(maxStorage: 24))

    instance.run(instructions: .pushInt32(24), .pushInt32(0x4536_2718), .WS, failure: .storageLocationOutOfBounds)
    instance.validate()
  }

  @Test func testWS_negativeIndex() {
    runNegativeTest(
      instructions: .pushInt32(-1),
      .pushInt32(0x4536_2718),
      .WS,
      failure: .storageLocationOutOfBounds
    )
  }

  // MARK: - RS 0x43
  /*
   Reads the value in the specified storage area location and pushes that value onto the stack.

   Pops a storage area location, n, from the stack and reads a 32-bit value, v, from that
   location. The value read is pushed onto the stack. The number of available storage locations
   is specified in the 'maxp' table in the font file'.
   */
  @Test func testRS() {
    let location: UInt = 0x03
    let value: Int32 = 0x1bd1

    var instance = getInstance()
    instance.setStorageValue(value, at: location)
    instance.run(instructions: .pushInt32(Int32(location)), .RS)

    instance.expectedEngineState.stack = [value]
    instance.validate()
  }

  @Test func testRS_indexOutOfBounds() {
    var instance = getInstance(maxp: .init(maxStorage: 24))

    instance.run(instructions: .pushInt32(24), .RS, failure: .storageLocationOutOfBounds)
    instance.validate()
  }

  @Test func testRS_negativeIndex() {
    runNegativeTest(instructions: .pushInt32(-1), .RS, failure: .storageLocationOutOfBounds)
  }

  @Test func testWSRS_storageAreaPersistsBetweenPrograms() {
    var instance = getInstance()

    let fpgm_loc: UInt8 = 0x01
    let fpgm_val: Int32 = 0x1bd1
    instance.run(.fpgm, instructions: [.NPUSHB([fpgm_loc]), .pushInt32(fpgm_val), .WS])

    let prep_loc: UInt8 = 0x02
    let prep_val: Int32 = 0x2ce2
    instance.expectedEngineState = nil
    instance.run(.prep, instructions: [.NPUSHB([prep_loc]), .pushInt32(prep_val), .WS, .NPUSHB([fpgm_loc]), .RS])
    instance.expectedEngineState.storage[1] = fpgm_val
    instance.expectedEngineState.storage[2] = prep_val
    instance.expectedEngineState.stack = [fpgm_val]
    instance.validate()

    instance.run(.glyf, instructions: [.NPUSHB([fpgm_loc]), .RS, .NPUSHB([prep_loc]), .RS])
    instance.expectedEngineState.storage[1] = fpgm_val
    instance.expectedEngineState.storage[2] = prep_val
    instance.expectedEngineState.stack = [prep_val, fpgm_val]
    instance.validate()
  }

  // MARK: - WCVTP 0x44
  /*
   Writes the value in pixels into the control value table location specified.

   Pops a value v and a control value table location l from the stack and puts that value in the
   specified location in the control value table. This instruction assumes the value taken from
   the stack is in pixels and not in FUnits. The value is written to the CVT table unchanged. The
   location l must be less than the number of storage locations specified in the 'maxp' table in
   the font file.
   */

  @Test func testWCVTP() {
    let location: UInt8 = 0x01
    let byte: UInt8 = 0x60

    var instance = getInstance()
    instance.run(.prep, instructions: [.NPUSHB([location, byte]), .WCVTP])

    instance.expectedEngineState.cvt[Int(location)] = F26Dot6(bitPattern: Int32(byte))
    instance.validate()
  }

  // bincompat: in FPGM CPP writes the value to CVT without scaling and only ever reads 0.
  @Test func testWCVTP_fpgm() {
    let location: UInt8 = 0x01
    let byte: UInt8 = 0x60
    let testVector = FixedVector<F2Dot14>.normalizing(x: 1, y: 0.5)
    var instance = getInstance()

    instance.run(
      .fpgm,
      instructions: [
        .PUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SPVFS,
        .PUSHB([location, byte]), .WCVTP,
        .PUSHB([location]), .RCVT,
      ]
    )
    instance.expectedEngineState.cvt[Int(location)] = F26Dot6(bitPattern: Int32(byte))
    instance.expectedEngineState.stack = [0]
    instance.expectedEngineState.variables.projectionVector = testVector
    instance.validate()
  }

  @Test func testWCVTP_stretchedWide() {
    var instance = getInstance()
    let testVector = FixedVector<F2Dot14>.normalizing(x: 1, y: 0.5)
    let value = F26Dot6(0.78125)
    instance.setScaleFactors(yStretch: 256)
    instance.run(
      .prep,
      instructions: [
        .PUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SPVFS,
        .PUSHB([2, UInt8(value.bitPattern)]), .WCVTP,

          .SPVTCA_Y, .PUSHB([0, UInt8(value.bitPattern)]), .WCVTP,

          .SPVTCA_X, .PUSHB([1, UInt8(value.bitPattern)]), .WCVTP,
      ]
    )
    instance.expectedEngineState.cvt[0] = value * 2
    instance.expectedEngineState.cvt[1] = value
    instance.expectedEngineState.cvt[2] = 0.96875
    instance.validate()
  }

  @Test func testWCVTP_OOB() {
    runNegativeTest(.fpgm, instructions: .PUSHW([1_024, 50]), .WCVTP, failure: .cvtLocationOutOfBounds)
    runNegativeTest(.prep, instructions: .PUSHW([1_024, 50]), .WCVTP, failure: .cvtLocationOutOfBounds)
    runNegativeTest(.glyf, instructions: .PUSHW([1_024, 50]), .WCVTP, failure: .cvtLocationOutOfBounds)
  }

  @Test func testWCVTP_tooFewStackElements() {
    runStackUnderflowTests(opcode: .WCVTP, parameters: 2)
  }

  // MARK: - RCVT 0x45
  /*
   Read a control value table entry and places its value onto the stack.

   Pops a CVT location from the stack and pushes the value found in the location specified onto the stack.
   */

  @Test func testRCVT() {
    let location: UInt8 = 0x01
    let byte: UInt8 = 0x32

    var instance = getInstance()
    instance.run(.prep, instructions: [.NPUSHB([location, byte]), .WCVTP, .NPUSHB([location]), .RCVT])

    instance.expectedEngineState.stack.append(Int32(byte))
    instance.expectedEngineState.cvt[Int(location)] = F26Dot6(bitPattern: Int32(byte))
    instance.validate()
  }

  @Test func testRCVT_stretchedWide() {
    var instance = getInstance()
    let testVector = FixedVector<F2Dot14>.normalizing(x: 1, y: 0.5)
    let value = F26Dot6(0.78125)
    instance.setScaleFactors(yStretch: 256)
    instance.run(
      .prep,
      instructions: [
        .SPVTCA_Y, .PUSHB([0, UInt8(value.bitPattern)]), .WCVTP,

          .SPVTCA_X, .PUSHB([1, UInt8(value.bitPattern)]), .WCVTP,

          .PUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SPVFS,
        .PUSHB([2, UInt8(value.bitPattern)]), .WCVTP,

          .PUSHB([0]), .RCVT,
        .PUSHB([1]), .RCVT,

          .SPVTCA_Y,
        .PUSHB([0]), .RCVT,
        .PUSHB([1]), .RCVT,

          .SPVTCA_X,
        .PUSHB([0]), .RCVT,
        .PUSHB([1]), .RCVT,
      ]
    )
    instance.expectedEngineState.stack = [
      value.bitPattern,
      (value * 2).bitPattern,
      (value / 2).bitPattern,
      value.bitPattern,
      F26Dot6(0.625).bitPattern,
      F26Dot6(1.234375).bitPattern,
    ]
    instance.expectedEngineState.cvt[0] = value * 2
    instance.expectedEngineState.cvt[1] = value
    instance.expectedEngineState.cvt[2] = 0.96875
    instance.validate()
  }

  @Test func testRCVT_stretchedWide_normal() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    let testVector = FixedVector<F2Dot14>.normalizing(x: 1, y: 0.5)
    let value = F26Dot6(0.78125)
    instance.setScaleFactors(yStretch: 256)
    instance.run(
      .prep,
      instructions: [
        .SPVTCA_Y, .PUSHB([0, UInt8(value.bitPattern)]), .WCVTP,
        .SPVTCA_X, .PUSHB([1, UInt8(value.bitPattern)]), .WCVTP,

          .PUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SPVFS,
        .PUSHB([2, UInt8(value.bitPattern)]), .WCVTP,

          .PUSHB([0]), .RCVT,
        .PUSHB([1]), .RCVT,
      ]
    )
    instance.setPoints([.zero, .init(x: 1, y: 0.5)], forZone: .glyph)
    instance.expectedEngineState.glyphPoints = instance.engineState().glyphPoints
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 1]), .SPVTL_1,
        .PUSHB([2]), .RCVT,
        .PUSHB([0]), .RCVT,
        .PUSHB([1]), .RCVT,
        .SPVTCA_X,
      ]
    )
    instance.expectedEngineState.stack = [32, 63, 39]
    instance.expectedEngineState.cvt[0] = value * 2
    instance.expectedEngineState.cvt[1] = value
    instance.expectedEngineState.cvt[2] = 0.96875
    instance.validate()
  }

  // Fuzzer-generated test that causes mixed-point multiplication between 26.6 and 16.16 to overflow
  @Test func testRCVT_roundHalfTowardPositive() {
    // Drives `mixedMulRoundingToNearestOrUp` through the rare
    // `remainder == half && product >= 0` tie-break case in
    // `Math.swift`. With cvtScale == xStretch * 16, effectiveCVTScale
    // is 1/16 (F16Dot16 bp = 4096), and a CVT entry with bitPattern 8
    // gives product = 32768, exactly half of the F16Dot16 divisor.
    var instance = getInstance(cvtCount: 1)
    instance.setScaleFactors(xStretch: 1, yStretch: 1, cvtScale: 16)
    instance.setCVT([F26Dot6(bitPattern: 8)])
    instance.run(.prep, instructions: [.PUSHB([0]), .RCVT])
    instance.expectedEngineState.cvt[0] = F26Dot6(bitPattern: 8)
    // 8 * (1/16) with round-half-up = bitPattern 1 (= 0.015625 in F26Dot6)
    instance.expectedEngineState.stack = [Int32(1)]
    instance.validate()
  }

  @Test func testRCVT_saturating() {
    var instance = getInstance(cvtCount: 1)
    instance.setCVT([.init(bitPattern: 0x6000_ffff)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: -65_536),
      yStretch: .init(bitPattern: 2_041_419),
      unitsPerEm: 19_275,
      pointSize: 2_164_157,
      cvtScale: .init(bitPattern: -32_769),
      isRotated: false,
      isStretched: false
    )
    instance.run(
      .notFpgm(),
      instructions: [
        .PUSHB([0]),
        .RCVT,
      ]
    )

    instance.expectedEngineState.stack = [.max]
    instance.validate()
  }

  @Test func testRCVT_OOB() {
    var instance = getInstance()
    instance.run(instructions: .PUSHW([.max]), .RCVT)

    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testRCVT_OOB_negative() {
    runNegativeTest(.notFpgm(), instructions: [.PUSHW([-1]), .RCVT], failure: .cvtLocationOutOfBounds)
  }

  // bincompat: no matter what might be in the cvt during fpgm (it already exists and can be written to),
  // CPP "reads" all zeroes for RCVT. so in-bound reads should consume the location operand and push 0 onto the stack.
  @Test func testRCVT_fpgm() {
    let location: UInt8 = 0x01
    let byte: UInt8 = 0x60
    let testVector = FixedVector<F2Dot14>.normalizing(x: 1, y: 0.5)
    var instance = getInstance()

    instance.run(
      .fpgm,
      instructions:
          .PUSHW([testVector.x.bitPattern, testVector.y.bitPattern]),
      .SPVFS,
      .NPUSHB([location, byte]),
      .WCVTP,
      .NPUSHB([location]),
      .RCVT
    )
    instance.expectedEngineState.cvt[Int(location)] = F26Dot6(bitPattern: Int32(byte))
    instance.expectedEngineState.variables.projectionVector = testVector
    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  // bincompat: in fpgm cpp absolutely does not care about the index and always gives you zero
  @Test func testRCVT_fpgm_negative() {
    var instance = getInstance()
    instance.run(.fpgm, instructions: .PUSHW([-1]), .RCVT)
    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testRCVT_OOBTight() {
    var instance = getInstance(cvtCount: 0)
    instance.run(instructions: .PUSHW([0]), .RCVT)

    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testRCVT_OOBTight2() {
    var instance = getInstance(cvtCount: 1)
    instance.setCVT([42])
    instance.run(instructions: .PUSHW([1]), .RCVT)

    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testRCVT_emptyStack() {
    runStackUnderflowTests(opcode: .RCVT, parameters: 1)
  }

  // MARK: - GC 0x46, 0x47
  /*
   Gets the coordinate value of the specified point using the current projection vector.

   Pops a point number p and pushes the coordinate value of that point on the current projection
   vector onto the stack. The value returned by GC[] is dependent upon the current direction of
   the projection vector.
   */

  @Test func testGC_onAxis_twilightZone() throws {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 1))

    instance.setPoints(
      [.init(scaled: .init(x: 12.56, y: 25.12), hinted: .init(x: 3.14, y: 6.28))],
      forZone: .twilight
    )

    let instructions: [HintingInstruction] = [
      .PUSHB([0]), .SZP2,  // set zp2 to the twilight zone
      .SPVTCA_X,  // first set the proj vector to X axis
      .PUSHB([0]), .GC_0,  // ... and get point 0's hinted coordinate
      .PUSHB([0]), .GC_1,  // ... and its scaled coordinate
      .SPVTCA_Y,  // then set the proj vector to Y axis
      .PUSHB([0]), .GC_0,  // ... and get point 0's hinted coordinate again
      .PUSHB([0]), .GC_1,  // ... and its scaled coordinate again
    ]
    instance.run(.glyf, instructions: instructions)

    instance.expectedEngineState.stack = [
      F26Dot6(25.12).bitPattern,
      F26Dot6(6.28).bitPattern,
      F26Dot6(12.56).bitPattern,
      F26Dot6(3.14).bitPattern,
    ]
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.validate()
  }

  @Test func testGC_aligned_twilightZone() throws {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 2))

    instance.setPoints([.zero, .init(x: 3.14, y: 6.28)], forZone: .twilight)

    let instructions: [HintingInstruction] = [
      .NPUSHB([0]), .SZPS,  // set all zp to the twilight zone
      .PUSHB([0, 1]),
      .SPVTL_0,  // set proj vector to the line from (3.14,6.28) to (0,0)

        .NPUSHB([1]),  // push point number 1
      .GC_0,  // ... and get point 1's coordinate along this vector
      // which should be its distance away from 0,0, negated,
      // because the proj vector is pointing the opposite way.
    ]
    instance.run(.glyf, instructions: instructions)

    // 7.02125344935
    instance.expectedEngineState.stack = [F26Dot6(-7.02125344935, rounding: .down).bitPattern]
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.variables.projectionVector = .init(
      x: .init(bitPattern: -7_327),
      y: .init(bitPattern: -14_654)
    )
    instance.validate()
  }

  @Test func testGC_divergingVectors() {
    var instance = getInstance(maxp: .init(maxPoints: 3))
    instance.setPoints(
      [
        .init(scaled: .init(x: 12.56, y: 25.12), hinted: .init(x: 3.14, y: 6.28)),
        .init(scaled: .init(x: 42, y: 0), hinted: .init(x: 0, y: 42)),
        .zero,
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions:
          .PUSHB([1, 2]),
      .SDPVTL_0,
      .PUSHB([0]),
      .GC_0,
      .PUSHB([0]),
      .GC_1
    )
    instance.expectedEngineState.stack = [F26Dot6(12.56).bitPattern, F26Dot6(6.28).bitPattern]
    instance.expectedEngineState.variables.dualProjectionVector = .init(x: 1, y: 0)
    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate()
  }

  @Test func testGC_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255]), .GC_0,
      ]
    )
    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  // MARK: - SCFS 0x48

  @Test func testSCFS_onAxis_twilightZone() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 1))
    let instructions: [HintingInstruction] = [
      // select twilight zone; SCFS uses zp2
      .NPUSHB([0]),
      .SZP2,

      // set freedom & projection vectors to X axis
      .SVTCA_X,

      // set point 0's coordinate to be 3.1 along projection vector,
      // by moving it along freedom vector. Because both are the X axis,
      // this effectively sets point 0's X value to 3.1
        .NPUSHB([0]),
      .pushF26Dot6(3.1),
      .SCFS,

      // set freedom & projection vectors to Y axis
      .SVTCA_Y,

      // set point 0's coordinate to be 9.8 along projection vector,
      // by moving it along freedom vector. Because both are the Y axis,
      // this effectively sets point 0's Y value to 9.8
        .NPUSHB([0]),
      .pushF26Dot6(9.8),
      .SCFS,
    ]

    instance.run(.prep, instructions: instructions)

    instance.expectedEngineState.twilightPoints[point: 0] = OutlinePoint(
      scaled: .init(x: 3.09375, y: 9.79687),
      hinted: .init(x: 3.1, y: 9.8),
      xMoved: true,
      yMoved: true
    )
    // vectors and engine variables aren't important for this test, this is just where we left them
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.zp2 = .twilight

    instance.validate()
  }

  @Test func testSCFS_onAxis_glyphZone() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 1))
    let instructions: [HintingInstruction] = [
      // select glyph zone; SCFS uses zp2
      .NPUSHB([1]),
      .SZP2,

      // set freedom & projection vectors to X axis
      .SVTCA_X,

      // set point 0's coordinate to be -3.1 along projection vector,
      // by moving it along freedom vector. Because both are the X axis,
      // this effectively sets point 0's X value to -3.1
        .NPUSHB([0]),
      .pushF26Dot6(-3.1),
      .SCFS,

      // set freedom & projection vectors to Y axis
      .SVTCA_Y,

      // set point 0's coordinate to be -9.8 along projection vector,
      // by moving it along freedom vector. Because both are the Y axis,
      // this effectively sets point 0's Y value to -9.8
        .NPUSHB([0]),
      .pushF26Dot6(-9.8),
      .SCFS,
    ]

    instance.run(.glyf, instructions: instructions)

    instance.expectedEngineState.glyphPoints[point: 0].moveTo(x: -3.1, y: -9.8, xMoved: true, yMoved: true)

    // vectors and engine variables aren't important for this test, this is just where we left them
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.zp2 = .glyph

    instance.validate()
  }

  @Test func testSCFS_offAxis1() throws {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 2))

    // Pick a freedom and projection vector and some distance to apply to the points
    let freedomVector = FixedVector<F2Dot14>(x: .init(bitPattern: 9_831), y: .init(bitPattern: 13_108))
    let projVector = FixedVector<F2Dot14>(x: freedomVector.y, y: freedomVector.x)
    let dist0: F26Dot6 = 3.1
    let dist1: F26Dot6 = 9.8

    let instructions: [HintingInstruction] = [
      // select twilight zone; SCFS uses zp2
      .NPUSHB([0]),
      .SZP2,

        .setFV(freedomVector),
      .setPV(projVector),

      // set point 0's coordinate to be dist0 along projection vector,
      // by moving it along freedom vector.
        .NPUSHW([0]),
      .pushF26Dot6(dist0),
      .SCFS,

      // set point 1's coordinate to be dist1 along projection vector,
      // by moving it along freedom vector.
        .NPUSHW([1]),
      .pushF26Dot6(dist1),
      .SCFS,
    ]

    instance.run(.prep, instructions: instructions)

    // I didn't do the math here, I just ran it through CPP interpreter, and this is what came out
    instance.expectedEngineState.twilightPoints[point: 0] = OutlinePoint(
      scaled: .init(x: 1.921875, y: 2.5625),
      hinted: .init(x: 1.921875, y: 2.5625),
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.twilightPoints[point: 1] = OutlinePoint(
      scaled: .init(x: 6.109375, y: 8.15625),
      hinted: .init(x: 6.109375, y: 8.15625),
      xMoved: true,
      yMoved: true
    )

    instance.expectedEngineState.variables.projectionVector = projVector
    instance.expectedEngineState.variables.freedomVector = freedomVector
    instance.expectedEngineState.variables.zp2 = .twilight

    instance.validate()
  }

  @Test func testSCFS_offAxis2() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 2))

    // Pick a freedom and projection vector and some distance to apply to the points
    let freedomVector = FixedVector<F2Dot14>.normalizing(x: 0.234, y: -0.9722365967)
    let projVector = FixedVector<F2Dot14>.normalizing(x: 0.1020304, y: -0.9947812812)
    let dist0: F26Dot6 = 6.625
    let dist1: F26Dot6 = -2.21875

    let instructions: [HintingInstruction] = [
      // select twilight zone; SCFS uses zp2
      .NPUSHB([0]),
      .SZP2,

        .setFV(freedomVector),
      .setPV(projVector),

      // set point 0's coordinate to be dist0 along projection vector,
      // by moving it along freedom vector.
        .NPUSHW([0]),
      .pushF26Dot6(dist0),
      .SCFS,

      // set point 1's coordinate to be dist1 along projection vector,
      // by moving it along freedom vector.
        .NPUSHW([1]),
      .pushF26Dot6(dist1),
      .SCFS,
    ]

    instance.run(.prep, instructions: instructions)

    // I didn't do the math here, I just ran it through CPP interpreter, and this is what came out
    instance.expectedEngineState.twilightPoints[point: 0] = OutlinePoint(
      scaled: .init(x: 1.5625, y: -6.484375),
      hinted: .init(x: 1.5625, y: -6.484375),
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.twilightPoints[point: 1] = OutlinePoint(
      scaled: .init(x: -0.515625, y: 2.171875),
      hinted: .init(x: -0.515625, y: 2.171875),
      xMoved: true,
      yMoved: true
    )

    instance.expectedEngineState.variables.projectionVector = projVector
    instance.expectedEngineState.variables.freedomVector = freedomVector
    instance.expectedEngineState.variables.zp2 = .twilight

    instance.validate()
  }

  @Test func testSCFS_orthogonal() {
    // See comment in GraphicsState about the minimum allowed dot product between the proj & free vectors.

    // I'm writing this test attached to SCFS (not to SFVFS, for instance) because this behavior is only
    // apparent when *using* the two vectors. The original values of the vectors are preserved in the
    // graphics state (e.g. for GFV).

    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 2))
    let instructions: [HintingInstruction] = [
      // select twilight zone; SCFS uses zp2
      .NPUSHB([0]),
      .SZP2,

      // set freedom & projection vectors to orthgonal vectors
      // (X and Y axes)
        .SFVTCA_X,
      .SPVTCA_Y,

      // set point 0's coordinate to be 3.1 along projection vector,
      // by moving it along freedom vector. Because the vectors
      // are orthogonal, the interpreter will give up and just
      // apply the 3.1 to the freedom vector (X axis).
        .NPUSHW([0]),
      .pushF26Dot6(3.1),
      .SCFS,

      // set freedom & projection vectors to orthogonal vectors
      .setFV(.normalizing(x: 0.326092, y: 0.945338)),
      .setPV(.normalizing(x: 0.945338, y: -0.326092)),

      // set point 1's coordinate to be 9.8 along projection vector,
      // by moving it along freedom vector. Because the vectors
      // are orthogonal, the interpreter will give up and just
      // apply the 9.8 to the freedom vector.
        .NPUSHW([1]),
      .pushF26Dot6(9.8),
      .SCFS,

      // clean up to simplify expected engine state
      .SVTCA_X,
    ]

    instance.run(.prep, instructions: instructions)

    let expectedX = F26Dot6(9.8).scaledIfRepresentable(by: (numerator: F2Dot14(0.326092), denominator: 1))!
    let expectedY = F26Dot6(9.8).scaledIfRepresentable(by: (numerator: F2Dot14(0.945338), denominator: 1))!

    instance.expectedEngineState.twilightPoints[point: 0] = OutlinePoint(
      scaled: .init(x: 3.09375, y: 0.0),
      hinted: .init(x: 3.1, y: 0),
      xMoved: true
    )
    instance.expectedEngineState.twilightPoints[point: 1] = OutlinePoint(
      scaled: .init(x: 3.1875, y: 9.265625),
      hinted: .init(x: expectedX, y: expectedY),
      xMoved: true,
      yMoved: true
    )

    instance.expectedEngineState.variables.projectionVector = .x_axis
    instance.expectedEngineState.variables.freedomVector = .x_axis
    instance.expectedEngineState.variables.zp2 = .twilight

    instance.validate()
  }

  @Test func testSCFS_tooFewStackElements() {
    runStackUnderflowTests(opcode: .SCFS, parameters: 2)
  }

  @Test func testSCFS_arbitrarilyLargePointCoords() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 2))

    let instructions: [HintingInstruction] = [
      .NPUSHB([0]), .SZP2,  // select twilight zone; SCFS uses zp2

      // Establish F26Dot6.max on the stack
        .pushF26Dot6(.max),

        .SVTCA_X,
      .PUSHB([0]),  // point index 0
      .PUSHB([2]), .CINDEX,  // F26Dot6.max
      .SCFS,  // Move point along the X axis

        .SVTCA_Y,
      .PUSHB([0]),  // point index 0
      .PUSHB([2]), .CINDEX,  // F26Dot6.max
      .SCFS,  // Move point along the Y axis

      // Do it again. The point should stay in the same place.

        .SVTCA_X,
      .PUSHB([0]),  // point index 0
      .PUSHB([2]), .CINDEX,  // F26Dot6.max
      .SCFS,  // Move point along the X axis

        .SVTCA_Y,
      .PUSHB([0]),  // point index 0
      .PUSHB([2]), .CINDEX,  // F26Dot6.max
      .SCFS,  // Move point along the Y axis

        .POP,  // Discard the F26Dot6.max from the stack
    ]

    instance.run(.prep, instructions: instructions)

    instance.expectedEngineState.twilightPoints[point: 0] = OutlinePoint(
      scaled: .init(x: .max, y: .max),
      hinted: .init(x: .max, y: .max),
      xMoved: true,
      yMoved: true
    )

    instance.expectedEngineState.variables.zp2 = .twilight
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.freedomVector = .y_axis

    instance.validate()
  }

  @Test func testSCFS_arithmeticOverflowByIllegalVectors() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 2))

    // Pick a freedom and projection vector and some distance to apply to the points
    let freedomVector = FixedVector<F2Dot14>(x: -2, y: -2)
    let projVector = FixedVector<F2Dot14>(x: -2, y: -2)
    let dist0: F26Dot6 = 6.625

    let instructions: [HintingInstruction] = [
      // select twilight zone; SCFS uses zp2
      .NPUSHB([0]),
      .SZP2,

        .setFV(freedomVector),
      .setPV(projVector),

      // Force the vectors to have their dot products computed using SCFS
      .NPUSHW([0]),
      .pushF26Dot6(dist0),
      .SCFS,
    ]

    instance.run(.prep, instructions: instructions)

    // It's ok if the expected value changes, this test's main purpose is to ensure the interpreter doesn't crash,
    // though the check remains useful as a way to notify us when our math changes in subtle ways that don't
    // affect the other tests.
    let expected = OutlinePoint(scaled: .init(x: -13.25, y: -13.25), xMoved: true, yMoved: true)
    instance.expectedEngineState.twilightPoints[point: 0] = expected

    instance.expectedEngineState.variables.projectionVector = projVector
    instance.expectedEngineState.variables.freedomVector = freedomVector
    instance.expectedEngineState.variables.zp2 = .twilight

    instance.validate()
  }

  @Test func testSCFS_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255, 255]), .SCFS,
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].move(to: .init(x: 3.984375, y: 0.0), xMoved: true)
    instance.validate()
  }

  @Test func testSCFS_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 3))
    instance.setPoints(
      [
        .init(scaled: .init(x: .min, y: .max))
      ],
      forZone: .glyph
    )

    instance.run(
      .glyf,
      instructions: [
        .PUSHW([F2Dot14.max.bitPattern, F2Dot14.max.bitPattern]), .SPVFS,
        .PUSHB([0]), .pushInt32(.max), .SCFS,
      ],
      failure: .arithmeticError
    )

    instance.validate(except: [.projectionVector, .points])
  }

  @Test func testSCFS_pedanticZoneChecks() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 0]), .SCFS,
      ],
      failure: .maxpLimitExceeded
    )
    instance.validate()
  }

  // Tracing indicated that yMoved was being set by STTI in a font where the reference did not.
  // This turned out to be because setting the freedom vector didn't reset GraphicsState.alwaysTouchAxis
  @Test func testSCFS_zeroFreedom() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 32))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    let instructions: [HintingInstruction] = [
      .PUSHB([0, 0]), .SFVFS,
      .PUSHW([11, .max]), .SCFS,
    ]

    instance.run(.glyf, instructions: instructions)
    instance.expectedEngineState.variables.freedomVector = .init(x: 0, y: 0)
    instance.validate()
  }

  // MARK: - MPPEM 0x4B
  @Test func testMPPEM() {
    var instance = getInstance()
    instance.run(.notFpgm(), instructions: [.MPPEM])
    instance.expectedEngineState.stack = [512]
    instance.validate()
  }

  @Test func testMPPEM_fpgm() {
    var instance = getInstance()
    instance.run(.fpgm, instructions: [.MPPEM])
    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testMPPEM_same_components() {
    // this is 512 even if the projection vector is wrong
    var instance = getInstance()
    instance.run(
      .glyf,
      instructions: [
        .setPV(.init(x: 1.75, y: 1.75)),
        .MPPEM,
        .SPVTCA_X,  // reset projection vector
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.stack = [512]
    instance.validate()
  }

  @Test func testMPPEM_diff_components() {
    // this is 1 even if the projection vector is wrong
    var instance = getInstance()
    instance.setScaleFactors(xStretch: 2, yStretch: 1)
    instance.run(
      .glyf,
      instructions: [
        .setPV(.init(x: 1.75, y: 1.75)),
        .MPPEM,
        .SPVTCA_X,  // reset projection vector
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.stack = [4]
    instance.validate()
  }

  // MARK: - MD[a] 0x49-0x4A Measure Distance
  /*
   Measures the distance between the two points specified.

   Depending upon the setting of the Boolean variable a, distance will be measured in the
   original outline or the grid-fitted outline. MD[0] measures the distance in the original
   outline while MD[1] measures the distance in the grid-fitted outline.
   */

  @Test func testMD0() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .init(original: .init(x: 256, y: 128)),
        .init(original: .init(x: 1_024, y: 2_048)),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: .SPVTCA_X, .PUSHB([0, 1]), .MD_0)
    instance.expectedEngineState.stack = [-12_288]
    instance.validate()
  }

  @Test func testMD0_roundingError() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 2_097_152),
      yStretch: .init(bitPattern: 2_097_152),
      unitsPerEm: 1_000,
      pointSize: 1
    )
    instance.setPoints(
      [
        .init(original: .init(x: 563, y: 122)),
        .init(original: .init(x: 0, y: 0)),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: .SPVTCA_Y, .PUSHB([0, 1]), .MD_0)
    instance.expectedEngineState.stack = [250]
    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate()
  }

  @Test func testMD0_roundingError2() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 2_097_152),
      yStretch: .init(bitPattern: 2_097_152),
      unitsPerEm: 1_000,
      pointSize: 1
    )
    instance.setPoints(
      [
        .init(original: .init(x: 563, y: 122)),
        .init(original: .init(x: 0, y: 0)),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: .PUSHW([1 << 13, 1 << 13]), .SPVFS, .PUSHB([0, 1]), .MD_0)
    instance.expectedEngineState.stack = [702]
    instance.expectedEngineState.variables.projectionVector = .init(x: 0.5, y: 0.5)
    instance.validate()
  }

  @Test func testMD1() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .init(scaled: .init(x: 2.56, y: 1.28)),
        .init(scaled: .init(x: 1.024, y: 2.048)),
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: .SPVTCA_X, .PUSHB([0, 1]), .MD_1)
    instance.expectedEngineState.stack = [98]
    instance.validate()
  }

  @Test func testMD_divergingVectors() {
    var instance = getInstance(maxp: .init(maxPoints: 4))
    instance.setPoints(
      [
        .init(original: .init(x: 256, y: 128), scaled: .init(x: 2.56, y: 1.28)),
        .init(original: .init(x: 1_024, y: 2_048), scaled: .init(x: 1.024, y: 2.048)),
        .init(scaled: .init(x: 42, y: 0), hinted: .init(x: 0, y: 42)),
        .zero,
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions:
          .PUSHB([2, 3]),
      .SDPVTL_0,
      .PUSHB([0, 1]),
      .MD_0,
      .PUSHB([0, 1]),
      .MD_1
    )
    instance.expectedEngineState.stack = [-49, -12_288]
    instance.expectedEngineState.variables.dualProjectionVector = .init(x: 1, y: 0)
    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate()
  }

  // Uses zp0 with point p1, zp1 with point p2
  @Test func testMD1_zones1() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.setPoints(
      [
        .init(scaled: .init(x: 2.56, y: 1.28))
      ],
      forZone: .glyph
    )
    instance.setPoints(
      [
        .init(scaled: .init(x: 1.024, y: 2.048))
      ],
      forZone: .twilight
    )
    instance.run(.glyf, instructions: .PUSHB([0, 0, 0]), .SZP1, .MD_1)
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.stack = [98]
    instance.validate()
  }

  @Test func testMD1_zones2() {
    var instance = getInstance(maxp: .init(maxPoints: 1, maxTwilightPoints: 1))
    instance.setPoints(
      [
        .init(scaled: .init(x: 2.56, y: 1.28))
      ],
      forZone: .twilight
    )
    instance.setPoints(
      [
        .init(scaled: .init(x: 1.024, y: 2.048))
      ],
      forZone: .glyph
    )
    instance.run(.glyf, instructions: .PUSHB([0, 0, 0]), .SZP0, .MD_1)
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.stack = [98]
    instance.validate()
  }

  // MD0 does not really make sense with the twilight zone as the original coords are always .zero, but it ought to work
  @Test func testMD0_zones() {
    var instance = getInstance(maxp: .init(maxTwilightPoints: 2))
    instance.setPoints(
      [
        .init(scaled: .init(x: 2.56, y: 1.28)),
        .init(scaled: .init(x: 1.024, y: 2.048)),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions:
          .SPVTCA_X,
      .PUSHB([0, 0, 0]),
      .SZPS,
      .MD_0,
      .PUSHB([1]),
      .SZPS
    )
    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testMD_stackUnderflow() {
    for opcode in [HintingInstruction.MD_1, .MD_0] {
      runStackUnderflowTests(.glyf, opcode: opcode, parameters: 2)
    }
  }

  @Test func testMD_correctUnscaledOutline() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        .init(original: .init(x: 100, y: 100), scaled: .init(x: 165, y: 165), hinted: .init(x: 150, y: 150)),
        .init(original: .init(x: 200, y: 200), scaled: .init(x: 550, y: 550), hinted: .init(x: 500, y: 500)),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0, .pushInt32(1), .SZP1,
        .SPVTCA_X,
        .pushInt32(0), .pushInt32(1), .MD_0,
      ],
      unscaledOutlineIsWrong: true
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.glyphPoints[point: 0].original = .init(x: 600, y: 600)
    instance.expectedEngineState.glyphPoints[point: 1].original = .init(x: 2_000, y: 2_000)
    instance.expectedEngineState.stack = [-22_400]
    instance.validate()
  }

  // Performance refactoring modified correctUnscaledOutline to grab the glyph zone or die trying,
  // which was a problem for MD, the one opcode that wasn't checking to see if the glyph zone existed first.
  // The reference had a redundant (from the non-MD opcodes' perspective) check in correctUnscaledOutline.
  @Test func testMD_dontReferenceGlyphZoneFromCorrectUnscaledOutlineWhenItsNotAvailable() {
    var instance = getInstance(maxp: .init(maxTwilightPoints: 2))
    instance.run(
      .prep,
      instructions: [
        .PUSHB([0]), .SZP0,
        .PUSHB([0]), .SZP1,
        .PUSHB([0, 1]), .MD_0,
        .POP,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.validate()
  }

  @Test func testMD_alwaysCorrectUnscaledOutlineWhenGlyphZoneIsAvailable() {
    var instance = getInstance(
      maxp: .init(
        version: 65_536,
        numGlyphs: 2_170,
        maxPoints: 17,  // 1 -> 17
        maxContours: 17_920,
        maxCompositePoints: 0,
        maxCompositeContours: 0,
        maxElements: 83,
        maxTwilightPoints: 49_012,
        maxStorage: 29_289,
        maxFunctionDefs: 25_701,
        maxInstructionDefs: 24_930,
        maxStackElements: 27_749,
        maxSizeOfInstructions: 19_456,
        maxComponentElements: 0,
        maxComponentDepth: 512
      ),
      cvtCount: 1
    )
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 2_046_820_352),
      yStretch: .init(bitPattern: 254),
      unitsPerEm: 0,
      pointSize: 0,
      cvtScale: .init(bitPattern: 255),
      isRotated: false,
      isStretched: false
    )
    instance.setPoints(
      [
        .init(
          original: .init(x: 0, y: 5_632),
          scaled: .init(x: 369.4375, y: 24_117_248.0),
          hinted: .init(x: 0.0, y: 124_928.0)
        ),
        .init(
          original: .init(x: 254, y: 0),
          scaled: .init(x: 0.0, y: 3.984375),
          hinted: .init(x: 0.0, y: 20_369_096.0),
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: -19_790, y: -21_683),
          scaled: .init(x: 20_197_376.0, y: 88.5),
          hinted: .zero,
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: 0, y: 19_018),
          scaled: .init(x: 19_435_522.4375, y: 9_736_192.25),
          hinted: .init(x: 0.0, y: 8_388_609.15625),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: 36, y: 256),
          scaled: .init(x: 0.0, y: 21_877_193.640625),
          hinted: .init(x: 26_318_213.53125, y: 28_415_280.0),
          yMoved: true
        ),
        .init(scaled: .init(x: 0.0, y: 1.90625), hinted: .init(x: 94_208.0, y: 0.0)),
        .init(
          scaled: .init(x: 491.984375, y: -4_096.015625),
          hinted: .init(x: -1_079.984375, y: 0.0),
          yMoved: true
        ),
        .init(
          original: .init(x: 19_724, y: 0),
          scaled: .init(x: 149_062.265625, y: 26_625_606.265625),
          hinted: .init(x: -28_949_501.734375, y: -28_948_921.734375),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: 8_995, y: 8_995),
          scaled: .init(x: 10_822.265625, y: -28_948_921.734375),
          hinted: .init(x: -29_079_993.734375, y: -29_037_568.0),
          yMoved: true
        ),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        // Set zone pointers to .twilight—MD isn't configured to modify the glyph zone!
        // ...but the reference behaviour is to do it anyways
        .PUSHB([0]), .SZPS,
        .PUSHB([0, 1]), .MD_0,
        .POP,
      ],
      unscaledOutlineIsWrong: true
    )

    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight

    instance.expectedEngineState.glyphPoints[point: 0].original = .init(x: 0, y: 244)
    instance.expectedEngineState.glyphPoints[point: 1].original = .init(x: 0, y: -25_753)
    instance.expectedEngineState.glyphPoints[point: 2].original = .zero
    instance.expectedEngineState.glyphPoints[point: 3].original = .init(x: 0, y: 16_384)
    instance.expectedEngineState.glyphPoints[point: 4].original = .init(x: -14_133, y: -10_037)
    instance.expectedEngineState.glyphPoints[point: 5].original = .init(x: 184, y: 0)
    instance.expectedEngineState.glyphPoints[point: 6].original = .init(x: -2, y: 0)
    instance.expectedEngineState.glyphPoints[point: 7].original = .init(x: 8_994, y: 8_995)
    instance.expectedEngineState.glyphPoints[point: 8].original = .init(x: 8_739, y: 8_822)

    instance.validate()
  }

  @Test func testMD_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255, 254]), .MD_0,
      ]
    )
    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  // MARK: - MPS 0x4C
  @Test func testMPS_72() {
    var instance = getInstance()
    instance.setScaleFactors(pointSize: 72)
    instance.run(.notFpgm(), instructions: [.MPS])
    instance.expectedEngineState.stack = [72]
    instance.validate()
  }

  @Test func testMPS_300() {
    var instance = getInstance()
    instance.setScaleFactors(pointSize: 300)
    instance.run(.notFpgm(), instructions: [.MPS])
    instance.expectedEngineState.stack = [300]
    instance.validate()
  }

  @Test func testMPS_fpgm() {
    var instance = getInstance()
    instance.run(.fpgm, instructions: [.MPS])
    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  // MARK: - FLIPON 0x4D, FLIPOFF 0x4E
  /*
   Sets the auto flip Boolean in the graphics state to TRUE/FALSE causing the MIRP[] and MIAP[]
   instructions to use the sign of control value table entries. When auto flip is set to FALSE,
   the direction in which distances are measured becomes significant. The default value for the
   auto flip state variable is TRUE.
   */

  @Test func testFLIPdefault() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([0x0]), .POP /* do nothing interesting, to get the default state */)
    instance.expectedEngineState.variables.autoFlip = true
    instance.validate()
  }
  @Test func testFLIPOFF() {
    var instance = getInstance()
    instance.run(instructions: .FLIPOFF)
    instance.expectedEngineState.variables.autoFlip = false
    instance.validate()
  }
  @Test func testFLIPON() {
    var instance = getInstance()
    instance.run(instructions: .FLIPON)
    instance.expectedEngineState.variables.autoFlip = true
    instance.validate()
  }
  @Test func testFLIPOFFON() {
    var instance = getInstance()
    instance.run(instructions: .FLIPOFF, .FLIPON)
    instance.expectedEngineState.variables.autoFlip = true
    instance.validate()
  }
  @Test func testFLIPONOFF() {
    var instance = getInstance()
    instance.run(instructions: .FLIPON, .FLIPOFF)
    instance.expectedEngineState.variables.autoFlip = false
    instance.validate()
  }

  // MARK: - DEBUG 0x4F

  @Test func testDEBUG() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([42]), .DEBUG)
    instance.validate()
  }

  @Test func testDEBUG_tooFewStackElements() {
    runStackUnderflowTests(opcode: .DEBUG, parameters: 1)
  }

  // MARK: - LT 0x50, LTEQ 0x51, GT 0x52, GTEQ 0x53
  /*
   LT: Compares the two number at the top of the stack. The test succeeds if the second of the
   two numbers is smaller than the first.
   LTEQ: Compares the two numbers at the top of the stack. The test succeeds if the second of the
   two numbers is smaller than or equal to the first.
   GT: Compares the two numbers at the top of the stack. The test succeeds if the second of the
   two numbers is larger than to the first.
   GTEQ: Compares the two numbers at the top of the stack. The test succeeds if the second of the
   two numbers is larger than or equal to the first.
   */
  @Test func testLT_LTEQ_GT_GTEQ() {
    func testCompareCase(_ a: Int32, _ b: Int32) {
      testCompareOneCase(a, b, op: .LT, result: a < b ? 1 : 0)
      testCompareOneCase(a, b, op: .LTEQ, result: a <= b ? 1 : 0)
      testCompareOneCase(a, b, op: .GT, result: a > b ? 1 : 0)
      testCompareOneCase(a, b, op: .GTEQ, result: a >= b ? 1 : 0)
    }
    func testCompareOneCase(_ a: Int32, _ b: Int32, op: HintingInstruction, result: Int32) {
      var instance = getInstance()
      instance.run(instructions: .pushInt32(a), .pushInt32(b), op)

      instance.expectedEngineState.stack = [result]
      instance.validate()
    }

    testCompareCase(0, 0)
    testCompareCase(0, 1)
    testCompareCase(1, 0)
    testCompareCase(2, 1)
    testCompareCase(1, 2)
    testCompareCase(2, 2)
    testCompareCase(-1, 1)
    testCompareCase(1, -1)
    testCompareCase(-1, -1)
    testCompareCase(-2, -1)
    testCompareCase(-1, -2)
    testCompareCase(Int32.max, 0)
    testCompareCase(Int32.max, Int32.min)
    testCompareCase(0, Int32.min)
  }

  @Test func testLT_LTEQ_GT_GTEQ_tooFewStackElements() {
    for opcode: HintingInstruction in [.LT, .LTEQ, .GT, .GTEQ] {
      runStackUnderflowTests(opcode: opcode, parameters: 2)
    }
  }

  // MARK: - EQ 0x54
  /*
   Tests whether the top two numbers on the stack are equal in value.
   Pops two 32 bit values, e2 and e1, from the stack and compares them. If they are the same,
   one, signifying TRUE is pushed onto the stack. If they are not equal, zero, signifying FALSE
   is placed onto the stack.
   */

  @Test func testEQ_true() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([0xaf, 0x44, 0x44]), .EQ)

    instance.expectedEngineState.stack = [1, 0xaf]
    instance.validate()
  }

  @Test func testEQ_false() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([0xce, 0x01, 0x02]), .EQ)

    instance.expectedEngineState.stack = [0, 0xce]
    instance.validate()
  }

  @Test func testEQ_tooFewStackElements() {
    runStackUnderflowTests(opcode: .EQ, parameters: 2)
  }

  // MARK: - NEQ 0x55
  /*
   Determines whether the two elements at the top of the stack are unequal.
   Pops two numbers, e2 and e1, from the stack and compares them. If they are different, one,
   signifying TRUE is pushed onto the stack. If they are equal, zero, signifying FALSE is pushed
   onto the stack.
   */

  @Test func testNEQ_true() {
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([0xce, 0x01, 0x02]), .NEQ])

    instance.expectedEngineState.stack = [1, 0xce]
    instance.validate()
  }

  @Test func testNEQ_false() {
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([0xaf, 0x44, 0x44]), .NEQ])

    instance.expectedEngineState.stack = [0, 0xaf]
    instance.validate()
  }

  @Test func testNEQ_tooFewStackElements() {
    runStackUnderflowTests(opcode: .NEQ, parameters: 2)
  }

  // MARK: - ODD 0x56
  @Test func testODD_emptyStack() {
    runStackUnderflowTests(opcode: .ODD, parameters: 1)
  }

  @Test func testODD() {
    let numbers = Self.extend(roundingSensitiveNumbers: Self.suggestedRoundingSensitiveNumbers())
    let rtg = RoundState.rtg
    for number in numbers {
      let isEven = rtg.round(number).integralPart.isMultiple(of: 2)
      var instance = getInstance()
      instance.run(instructions: [
        .pushF26Dot6(number), .ODD,
      ])
      instance.expectedEngineState.stack = [isEven ? 0 : 1]
      instance.validate()
    }
  }

  // MARK: - EVEN 0x57
  @Test func testEVEN_emptyStack() {
    runStackUnderflowTests(opcode: .EVEN, parameters: 1)
  }

  @Test func testEVEN() {
    let numbers = Self.extend(roundingSensitiveNumbers: Self.suggestedRoundingSensitiveNumbers())
    let rtg = RoundState.rtg
    for number in numbers {
      let isEven = rtg.round(number).integralPart.isMultiple(of: 2)
      var instance = getInstance()
      instance.run(instructions: [
        .pushF26Dot6(number), .EVEN,
      ])
      instance.expectedEngineState.stack = [isEven ? 1 : 0]
      instance.validate()
    }
  }

  // MARK: - AND 0x5A
  /*
   Takes the logical and of the top two stack elements.
   */

  @Test func testAND() {
    func testANDCase(_ a: Int32, _ b: Int32, result: Int32) {
      var instance = getInstance()
      instance.run(instructions: .pushInt32(a), .pushInt32(b), .AND)

      instance.expectedEngineState.stack = [result]
      instance.validate()
    }
    testANDCase(0, 0, result: 0)
    testANDCase(0, 1, result: 0)
    testANDCase(0, 2, result: 0)
    testANDCase(0, 0, result: 0)
    testANDCase(1, 0, result: 0)
    testANDCase(2, 0, result: 0)
    testANDCase(1, 1, result: 1)
    testANDCase(2, 2, result: 1)
    testANDCase(Int32.max, 0, result: 0)
    testANDCase(Int32.min, 0, result: 0)
    testANDCase(0, Int32.max, result: 0)
    testANDCase(0, Int32.min, result: 0)
    testANDCase(Int32.max, Int32.min, result: 1)
    testANDCase(Int32.min, Int32.max, result: 1)
    testANDCase(Int32.max, Int32.max, result: 1)
    testANDCase(Int32.min, Int32.min, result: 1)
  }

  @Test func testAND_tooFewStackElements() {
    runStackUnderflowTests(opcode: .AND, parameters: 2)
  }

  // MARK: - OR 0x5B
  /*
   Takes the logical or of the two numbers at the top of the stack.
   */

  @Test func testOR() {
    func testORCase(_ a: Int32, _ b: Int32, result: Int32) {
      var instance = getInstance()
      instance.run(instructions: .pushInt32(a), .pushInt32(b), .OR)

      instance.expectedEngineState.stack = [result]
      instance.validate()
    }
    testORCase(0, 0, result: 0)
    testORCase(0, 1, result: 1)
    testORCase(0, 2, result: 1)
    testORCase(0, 0, result: 0)
    testORCase(1, 0, result: 1)
    testORCase(2, 0, result: 1)
    testORCase(1, 1, result: 1)
    testORCase(2, 2, result: 1)
    testORCase(Int32.max, 0, result: 1)
    testORCase(Int32.min, 0, result: 1)
    testORCase(0, Int32.max, result: 1)
    testORCase(0, Int32.min, result: 1)
    testORCase(Int32.max, Int32.min, result: 1)
    testORCase(Int32.min, Int32.max, result: 1)
    testORCase(Int32.max, Int32.max, result: 1)
    testORCase(Int32.min, Int32.min, result: 1)
  }

  @Test func testOR_tooFewStackElements() {
    runStackUnderflowTests(opcode: .OR, parameters: 2)
  }

  // MARK: - NOT 0x5C
  /*
   Takes the logical negation of the number at the top of the stack.
   */

  @Test func testNOT_zero() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([0]), .NOT)

    instance.expectedEngineState.stack = [1]
    instance.validate()
  }

  @Test func testNOT_one() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([1]), .NOT)

    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testNOT_largeNumber() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([255]), .NOT)

    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testNOT_tooFewStackElements() {
    runStackUnderflowTests(opcode: .NOT, parameters: 1)
  }

  // MARK: - DELTAP1 0x5D
  // see DELTAC tests for edge case tests; DELTAP and DELTAC share their
  // implementation
  @Test func testDELTAP1() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: 2, y: 2),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(503), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(1),
        .pushInt32(1), .DELTAP1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2.125, y: 2, xMoved: true)
    instance.validate()
  }

  // …except only the DELTAP opcodes require a zone…
  @Test func testDELTAP1_noZone() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .prep,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(503), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(1),
        .pushInt32(1), .DELTAP1,
      ],
      failure: .invalidAccessToGlyphZone
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.validate(except: kErrorExceptions)
  }

  // …and only the DELTAP opcodes check their zone…
  @Test func testDELTAP1_twilightInFpgm_outOfRangePpem() {
    // In .fpgm with zp0 == .twilight, DELTAP enters the early-return branch
    // only after `delta` exits without invoking its closure — which happens
    // when `fakePixelsPerEM` is outside `0..<kDeltaPhaseStride`. With a
    // large deltaBase, fakePixelsPerEM is negative and we return cleanly.
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.run(
      .fpgm,
      instructions: [
        .pushInt32(0), .SZP0,  // twilight
        .pushInt32(503), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(1),
        .pushInt32(1), .DELTAP1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.validate()
  }

  // …and DELTAP throws `.invalidAccessToTwilightZone` once the closure actually
  // runs (zp0=twilight + program=fpgm + a delta pair whose PPEM matches).
  @Test func testDELTAP1_twilightInFpgm_throwsInvalidAccess() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2))
    instance.run(
      .fpgm,
      instructions: [
        .pushInt32(0), .SZP0,
        // Default fpgm `projectedIntegerPPEM` is 0; setting deltaBase to 0
        // makes `fakePixelsPerEM` land at 0 so the delta pair below matches.
        .pushInt32(0), .SDB,
        .pushInt32(0 << 4 | 8), .pushInt32(1),
        .pushInt32(1), .DELTAP1,
      ],
      failure: .invalidAccessToTwilightZone
    )
    instance.expectedEngineState.variables.deltaBase = 0
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.validate(except: kErrorExceptions)
  }

  @Test func testDELTAP1_pedanticZoneChecks() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: 2, y: 2),
        .zero, .zero,
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(503), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(1),
        .pushInt32(1), .DELTAP1,
      ],
      failure: .maxpLimitExceeded
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.validate()
  }

  // …and the DELTAP opcodes check the stack before the zone…
  @Test func testDELTAP1_pedanticStackChecksBeforeZone() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .prep,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(503), .SDB,
        .pushInt32(0), .DELTAP1,
        .pushInt32(42),
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  // …and really only check the zone if the opcode actually modifies a point…
  @Test func testDELTAP1_onlyCheckZoneWhenNecessary() {
    var instance = getInstance(
      maxp: .init(
        version: 65_536,
        numGlyphs: 65_280,
        maxPoints: 0,
        maxContours: 0,
        maxCompositePoints: 5_120,
        maxCompositeContours: 0,
        maxElements: 32_930,
        maxTwilightPoints: 17_551,
        maxStorage: 35_584,
        maxFunctionDefs: 0,
        maxInstructionDefs: 0,
        maxStackElements: 185,
        maxSizeOfInstructions: 5,
        maxComponentElements: 256,
        maxComponentDepth: 46
      )
    )
    // Found by a fuzzer, in case it wasn't obvious.
    instance.run(
      .fpgm,
      instructions: [
        75, 75, 61, 75, 75, 75, 75, 27, 190, 0, 65, 0, 0, 0, 0, 0, 0, 0, 0, 169, 15, 206, 10, 2, 0, 0, 0, 0, 0,
        0, 0, 0, 0, 179, 179, 75, 75, 0, 75, 89, 75, 75, 75, 75, 32, 75, 79, 83, 116, 114, 105, 100, 101, 97,
        98, 108, 101, 0, 0, 98, 104, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        0, 0, 0,
      ].map { .literal($0) }
    )

    instance.validate(except: kErrorExceptions.union(.roundState))
  }

  // …or make use of movePoint
  @Test func testDELTAPx_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: .max, y: 2),
      ],
      forZone: .glyph
    )

    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(503), .SDB,
        .setFV(.init(x: .max, y: .max)),
        .pushInt32(9 << 4 | 8), .pushInt32(1),
        .pushInt32(1), .DELTAP1,
      ],
      failure: .arithmeticError
    )

    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.variables.freedomVector = .init(x: .max, y: .max)
    instance.validate(except: .points)
  }

  // MARK: - SDB 0x5E
  @Test func testSDB_stackunderflow() {
    runStackUnderflowTests(opcode: .SDB, parameters: 1)
  }

  @Test func testSDB_smallvalue() {
    var instance = getInstance()
    instance.run(instructions: .pushInt32(0x0101), .SDB)
    instance.expectedEngineState.variables.deltaBase = 0x0101
    instance.validate()
  }

  @Test func testSDB_largevalue() {
    var instance = getInstance()
    instance.run(instructions: .pushInt32(0xff0101), .SDB)
    instance.expectedEngineState.variables.deltaBase = 0x0101
    instance.validate()
  }

  // MARK: - SDS 0x5F
  @Test func testSDS_stackunderflow() {
    runStackUnderflowTests(opcode: .SDS, parameters: 1)
  }

  @Test func testSDS_smallvalue() {
    var instance = getInstance()
    instance.run(instructions: .pushInt32(0x0101), .SDS)
    instance.expectedEngineState.variables.deltaShift = 0x0101
    instance.validate()
  }

  @Test func testSDS_largevalue() {
    var instance = getInstance()
    instance.run(instructions: .pushInt32(0xff0101), .SDS)
    instance.expectedEngineState.variables.deltaShift = 0x0101
    instance.validate()
  }

  // MARK: - ADD 0x60
  /*
   Pops two 26.6 fixed point numbers, n2 and n1, off the stack and pushes the sum of those two numbers onto the stack.
   */

  @Test func testADD() {
    func testADDCase(_ a: F26Dot6, _ b: F26Dot6, expects result: F26Dot6) {
      var instance = getInstance()
      instance.run(instructions: .pushF26Dot6(a), .pushF26Dot6(b), .ADD)
      instance.expectedEngineState.stack = [result.bitPattern]
      instance.validate()
    }

    testADDCase(0.0, 0.546875, expects: 0.546875)
    testADDCase(0.546875, 0.0, expects: 0.546875)
    testADDCase(1.609375, 1.078125, expects: 2.6875)
    testADDCase(1.078125, 1.609375, expects: 2.6875)
    testADDCase(3.984375, 3.984375, expects: 7.96875)
    testADDCase(3.75, 3.4375, expects: 7.1875)

    testADDCase(.min, .min, expects: 0.0)
    testADDCase(.min, .max, expects: .init(bitPattern: -0x1))
    testADDCase(.max, .min, expects: .init(bitPattern: -0x1))
    testADDCase(.max, .max, expects: .init(bitPattern: -0x2))

    // These numbers are mostly randomly generated. Not some clever combination
    // that maximizes coverage of interesting values.
    testADDCase(32_356_594.53125, 7_270_268.390625, expects: -27_482_001.078125)
    testADDCase(5_239_207.140625, 10_520_083.734375, expects: 15_759_290.875)
    testADDCase(30_980_271.875, 30_128_075.234375, expects: -6_000_516.890625)
    testADDCase(11_906_070.828125, -21_155_687.15625, expects: -9_249_616.328125)
    testADDCase(-2_681_779.96875, 5_725_914.765625, expects: 3_044_134.796875)
    testADDCase(12_420_142.9375, 11_967_619.0625, expects: 24_387_762.0)
    testADDCase(32_602_060.984375, -28_255_123.140625, expects: 4_346_937.84375)
    testADDCase(-8_566_901.0625, -16_304_176.34375, expects: -24_871_077.40625)
  }

  @Test func testADD_tooFewStackElements() {
    runStackUnderflowTests(opcode: .ADD, parameters: 2)
  }

  // MARK: - SUB 0x61
  /*
   Subtracts the number at the top of the stack from the number below it. Pops two 26.6 numbers,
   n1 and n2, from the stack and pushes the difference between the two elements onto the stack.
   */

  @Test func testSUB() {
    func testSUBCase(_ n1: F26Dot6, _ n2: F26Dot6, expects result: F26Dot6) {
      var instance = getInstance()
      instance.run(instructions: .pushF26Dot6(n1), .pushF26Dot6(n2), .SUB)
      instance.expectedEngineState.stack = [result.bitPattern]
      instance.validate()
    }

    testSUBCase(0.0, 0.546875, expects: -0.546875)
    testSUBCase(0.546875, 0.0, expects: 0.546875)
    testSUBCase(1.078125, 1.609375, expects: -0.53125)
    testSUBCase(3.984375, 3.984375, expects: 0.0)
    testSUBCase(3.75, 3.4375, expects: 0.3125)

    testSUBCase(.min, 0.0, expects: .min)
    testSUBCase(0.0, .min, expects: .min)
    testSUBCase(.max, 0.0, expects: .max)
    testSUBCase(0.0, .max, expects: -.max)
    testSUBCase(.min, .min, expects: 0.0)
    testSUBCase(.min, .max, expects: .init(bitPattern: 0x1))
    testSUBCase(.max, .min, expects: .init(bitPattern: -0x1))
    testSUBCase(.max, .max, expects: 0.0)

    // These numbers are mostly randomly generated. Not some clever combination
    // that maximizes coverage of interesting values.
    testSUBCase(17_879_511.28125, 32_247_236.46875, expects: -14_367_725.1875)
    testSUBCase(10_095_507.265625, 31_512_755.453125, expects: -21_417_248.1875)
    testSUBCase(-11_795_212.875, -14_231_247.375, expects: 2_436_034.5)
    testSUBCase(15_265_658.6875, 16_315_271.5625, expects: -1_049_612.875)
    testSUBCase(-2_367_712.765625, -17_794_324.015625, expects: 15_426_611.25)
    testSUBCase(-28_767_954.625, 29_256_528.671875, expects: 9_084_380.703125)
    testSUBCase(2_348_114.4375, -5_637_423.03125, expects: 7_985_537.46875)
  }

  @Test func testSUB_tooFewStackElements() {
    runStackUnderflowTests(opcode: .SUB, parameters: 2)
  }

  // MARK: - DIV 0x62
  /*
   Divides the number second from the top of the stack by the number at the top of the stack.
   Pops two 26.6 fixed point numbers, n1 and n2 off the stack and pushes onto the stack the
   quotient obtained by dividing n2 by n1. The division takes place in the following fashion,
   n1 is shifted left by six bits and then divided by n2.
   */

  @Test func testDIV() {
    func testDIVCase(_ a: F26Dot6, _ b: F26Dot6, expects result: F26Dot6) {
      var instance = getInstance()
      instance.run(instructions: .pushF26Dot6(a), .pushF26Dot6(b), .DIV)
      instance.expectedEngineState.stack = [result.bitPattern]
      instance.validate()
    }

    testDIVCase(0.0, 0.546875, expects: .init(bitPattern: 0x00))  // 0.0

    // 0x45 << 6 = 0x1140 ; 0x1140 / 0x67 = 0x2A
    testDIVCase(1.078125, 1.609375, expects: .init(bitPattern: 0x2A))  // 0.65625

    // 0x67 << 6 = 0x19C0 ; 0x19C0 / 0x45 = 0x5F
    testDIVCase(1.609375, 1.078125, expects: .init(bitPattern: 0x5F))  // 1.484375

    // 0xFF << 6 = 0x3FC0 ; 0x3FC0 / 0xFF = 0x40 (== 1 << 6)
    testDIVCase(3.984375, 3.984375, expects: .init(bitPattern: 0x40))  // 1.0

    // 0xF0 << 6 = 0x3C00 ; 0x3C00 / 0xDC = 0x45
    testDIVCase(3.75, 3.4375, expects: .init(bitPattern: 0x45))  // 1.078125

    testDIVCase(.min, .min, expects: .init(bitPattern: 0x40))  // 1.0
    testDIVCase(.max, .min, expects: .init(bitPattern: Int32(bitPattern: 0xFFFF_FFC1)))  // -0.984375
    testDIVCase(.min, .max, expects: .init(bitPattern: Int32(bitPattern: 0xFFFF_FFC0)))  // -1.0
    testDIVCase(.max, .max, expects: .init(bitPattern: 0x40))  // 1.0

    // The following numbers are randomly generated. Not some clever combination
    // that maximizes coverage of interesting values.
    // -1.171875
    testDIVCase(-12_906_569.625, 10_932_689.78125, expects: .init(bitPattern: Int32(bitPattern: 0xFFFF_FFB5)))
    // -36.984375
    testDIVCase(21_507_521.90625, -581_357.953125, expects: .init(bitPattern: Int32(bitPattern: 0xFFFF_F6C1)))
    // -0.421875
    testDIVCase(-5_516_180.515625, 12_724_933.890625, expects: .init(bitPattern: Int32(bitPattern: 0xFFFF_FFE5)))
    testDIVCase(-32_542_990.625, -14_107_179.40625, expects: .init(bitPattern: 0x93))  // 2.296875
    testDIVCase(149_834.078125, 5_339_431.015625, expects: .init(bitPattern: 0x01))  // 0.015625
    testDIVCase(7_257_169.359375, 19_615_316.234375, expects: .init(bitPattern: 0x17))  // 0.359375
    // -78413.453125
    testDIVCase(26_357_951.171875, -336.140625, expects: .init(bitPattern: Int32(bitPattern: 0xFFB3_6CA3)))
    // -1452155.015625
    testDIVCase(-29_882_627.578125, 20.578125, expects: .init(bitPattern: Int32(bitPattern: 0xFA75_E13F)))
    testDIVCase(28_748_564.8125, -54.03125, expects: .init(bitPattern: Int32(bitPattern: 0xFDF8_65C6)))  // -532072.90625
    testDIVCase(-69_499.609375, -16.078125, expects: .init(bitPattern: 0x438A7))  // 4322.609375
    testDIVCase(1.0, 0.0, expects: .max)  // 33554431.984375
    testDIVCase(0.0, 0.0, expects: .max)  // 33554431.984375
    testDIVCase(-1.0, 0.0, expects: .min)  // -33554432.0
  }

  @Test func testDIV_tooFewStackElements() {
    runStackUnderflowTests(opcode: .DIV, parameters: 2)
  }

  // MARK: - IF 0x58 / ELSE 0x1B / EIF 0x59
  /*
   Marks the beginning of an if-statement.
   Pops an integer, e, from the stack. If e is zero (FALSE), the instruction pointer is moved to
   the associated ELSE or EIF[] instruction in the instruction stream. If e is nonzero (TRUE),
   the next instruction in the instruction stream is executed. Execution continues until the
   associated ELSE[] instruction is encountered or the associated EIF[] instruction ends the
   IF[] statement. If an associated ELSE[] statement is found before the EIF[], the instruction
   pointer is moved to the EIF[] statement.
   The ELSE portion of an IF-ELSE-EIF sequence is optional.

   An unusual behavior of the old interpreter, that we preserve, is that any encounter of ELSE
   causes the interpreter to seek until EIF, even when it's already executing the ELSE path and
   no additional IF opcodes were encountered. An ELSE branch therefore ends, in addition to EIF,
   with ELSE -- in which case execution resumes after the matching EIF just as if the path had
   not contained the extra ELSE and any extra non-EIF instructions. It follows that an
   "unassociated" ELSE also causes the interpreter to seek until EIF. This effectively comments
   out the intervening instructions.

   Another unusual behavior is that a missing EIF is not necessarily fatal. If no EIF is found
   while on the path that's taken, IF and ELSE will behave as if the EIF is just after the end
   of the program. A missing EIF is only fatal to the program if it's on the path that's NOT
   taken. This includes being on an ELSE path that contains an extraneous ELSE since that
   convinces the interpreter it's on the not-taken path.
   */

  @Test func testIfEif_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .EIF,
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testIfEif_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElseEif_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testIfElseEif_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [99]
    instance.validate()
  }

  @Test func testIf_missingEif() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      // implied .EIF at end of program
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testIf_missingEif_notTaken() {
    runNegativeTest(
      instructions: .NPUSHB([0]),
      .IF,
      .NPUSHB([42]) /* missing .EIF */,
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testIfElse_missingEif() {
    runNegativeTest(
      instructions: .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]) /* missing .EIF */,
      expectingProperties: [.stack([42])],
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testIfElse_missingEif_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      // implied .EIF at end of program
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [99]
    instance.validate()
  }

  @Test func testIf_emptyStack() {
    runNegativeTest(instructions: .IF, .NPUSHB([42]), .EIF, failure: .stackUnderflow)
  }

  @Test func testIf_emptyStackAndMissingEif() {
    runNegativeTest(instructions: .IF, .NPUSHB([42]), failure: .stackUnderflow)
  }

  @Test func testIfEif_skipNPUSHB_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .EIF,
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [42, 0x59]
    instance.validate()
  }

  @Test func testIfEif_skipNPUSHB_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  // Let's test NPUSHB is skipped in all possible combinations where it
  // needs to be skipped, and test that the other 3 PUSH instructions once
  // each. We don't need to fill this entire test grid.

  @Test func testIfEif_skipPUSHB_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .PUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfEif_skipNPUSHW_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHW([0x5900]),  // .EIF
      .NPUSHB([42]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfEif_skipPUSHW_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .PUSHW([0x5900]),  // .EIF
      .NPUSHB([42]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElseEif_skipNPUSHB_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [42, 0x59]
    instance.validate()
  }

  @Test func testIfElseEif_skipNPUSHB_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [99]
    instance.validate()
  }

  @Test func testIfEif_nested1_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testIfEif_nested1_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElseEif_nested1_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testIfElseEif_nested1_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [99]
    instance.validate()
  }

  @Test func testIf_nested1_missingEif() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .EIF,
      // implied .EIF at end of program
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testIf_nested1_missingEif_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .EIF,
      // implied .EIF at end of program
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElse_nested1_missingEif() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      // implied .EIF at end of program
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testIfElse_nested1_missingEif_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      // implied .EIF at end of program
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [99]
    instance.validate()
  }

  @Test func testIf_nestedX_emptyStack() {
    runNegativeTest(instructions: .IF, .NPUSHB([1]), .IF, .NPUSHB([42]), .EIF, .EIF, failure: .stackUnderflow)
  }

  @Test func testIf_nested1_emptyStackAndMissingEif() {
    runNegativeTest(
      instructions: .NPUSHB([1]),
      .IF,
      .IF,
      .NPUSHB([42]),
      .EIF /* missing .EIF */,
      failure: .stackUnderflow
    )
  }

  @Test func testIfEif_nested1_skipNPUSHB_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = [42, 0x59]
    instance.validate()
  }

  @Test func testIfEif_nested1_skipNPUSHB_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElseEif_nested1_skipNPUSHB_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [42, 0x59]
    instance.validate()
  }

  @Test func testIfElseEif_nested1_skipNPUSHB_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [99]
    instance.validate()
  }

  @Test func testIfEif_nested0_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfEif_nested0_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElseEif_nested0_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElseEif_nested0_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIf_nested0_missingEif() {
    runNegativeTest(
      instructions: .NPUSHB([0]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .EIF /* missing .EIF */,
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testIf_nested0_missingEif_notTaken() {
    runNegativeTest(
      instructions: .NPUSHB([0]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .EIF /* missing .EIF */,
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testIfElse_nested0_missingEif() {
    runNegativeTest(
      instructions: .NPUSHB([0]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF /* missing .EIF */,
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testIfElse_nested0_missingEif_notTaken() {
    runNegativeTest(
      instructions: .NPUSHB([0]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF /* missing .EIF */,
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testIf_nested0_emptyStackAndMissingEif() {
    runNegativeTest(
      instructions: .NPUSHB([0]),
      .IF,
      .IF,
      .NPUSHB([42]),
      .EIF /* missing .EIF */,
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testIfEif_nested0_skipNPUSHB_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfEif_nested0_skipNPUSHB_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElseEif_nested0_skipNPUSHB_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([1]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIfElseEif_nested0_skipNPUSHB_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0]),
      .IF,
      .NPUSHB([0x59]),  // .EIF
      .NPUSHB([42]),
      .ELSE,
      .NPUSHB([99]),
      .EIF,
      .EIF,
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testEIF_stray() {
    var instance = getInstance()
    instance.run(instructions: .EIF)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testELSE_emptyExpression() {
    var instance = getInstance()
    instance.run(instructions: .ELSE, .EIF)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testELSE_stray() {
    runNegativeTest(instructions: .ELSE, failure: .ranOffEndOfInstructions)
  }

  @Test func testELSE_stray_withEIF() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([1]), .ELSE, .PUSHB([2]), .EIF, .PUSHB([3]))
    instance.expectedEngineState.stack = [3, 1]
    instance.validate()
  }

  // bincompat: cpp does not care!
  // when an else is encountered in the middle of execution it is assumed that we've arrived at the end of an IF branch
  // which we took. so then the interpreter decides to seek until EIF is encountered, skipping everything in between.
  @Test func testELSE_extraneous_notTaken() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([0]), .IF, .ELSE, .PUSHB([42]), .ELSE, .PUSHB([84]), .ELSE, .CLEAR, .EIF)
    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  // bincompat: cpp does not care!
  @Test func testELSE_extraneous_taken() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([1]), .IF, .ELSE, .ELSE, .ELSE, .EIF)
    instance.validate()
  }

  // because we're seeking an EIF
  @Test func testELSE_extraneous_missingEIF_notTaken() {
    runNegativeTest(instructions: .PUSHB([0]), .IF, .ELSE, .ELSE, .ELSE, failure: .ranOffEndOfInstructions)
  }

  @Test func testELSE_extraneous_missingEIF_taken() {
    runNegativeTest(instructions: .PUSHB([1]), .IF, .ELSE, .ELSE, .ELSE, failure: .ranOffEndOfInstructions)
  }

  @Test func testIF_deeplyNested() {
    var instance = getInstance()
    let depth = 128
    let instructions: [HintingInstruction] = [
      [.NPUSHB(.init(repeating: 1, count: depth))],
      .init(repeating: .IF, count: depth),
      .init(repeating: .EIF, count: depth),
    ].flatMap(\.self)
    instance.run(instructions: instructions)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIF_consecutive() {
    var instance = getInstance()
    instance.run(instructions: .PUSHB([33, 1, 1]), .IF, .IF, .EIF, .EIF, .PUSHB([77]))
    instance.expectedEngineState.stack = [77, 33]
    instance.validate()
  }

  // MARK: - MUL 0x63
  /*
   Multiplies the top two numbers on the stack. Pops two 26.6 numbers, n2 and n1, from the stack
   and pushes onto the stack the product of the two elements. The 52.12 result is shifted right
   by 6 bits and the high 26 bits are discarded yielding a 26.6 result.
   */

  @Test func testMUL() {
    func testMULCase(_ a: F26Dot6, _ b: F26Dot6, expects result: F26Dot6) {
      var instance = getInstance()
      instance.run(instructions: .pushF26Dot6(a), .pushF26Dot6(b), .MUL)
      instance.expectedEngineState.stack = [result.bitPattern]
      instance.validate()
    }

    // In the following cases, the rounding behavior of the multiply operation is essential.
    // The correct rounding mode differs based on the magnitude of the parameters.
    testMULCase(-2.140625, 0.5, expects: -1.0625)
    testMULCase(-0.546875, 0.5, expects: -0.265625)
    testMULCase(-1.984375, 0.5, expects: -0.984375)
    testMULCase(-2.015625, 0.5, expects: -1.0)
    testMULCase(-2.171875, 0.5, expects: -1.078125)
    testMULCase(9_441.3125, 17_569.125, expects: 31_657_871.484375)
    testMULCase(9_441.3125, 17_569.140625, expects: 31_658_019.0)
    testMULCase(17_434_187.453125, 31_016_309.40625, expects: -14_901_937.328125)
    testMULCase(12_094_053.625, -11_084_581.828125, expects: 12_101_587.71875)
    testMULCase(25_320_698.1875, 14_954_802.828125, expects: -11_222_771.4375)
    testMULCase(12_498_758.5, -10_364_476.703125, expects: -32_539_747.578125)

    testMULCase(.min, .min, expects: 0.0)
    testMULCase(.min, .max, expects: 524_288.0)
    testMULCase(.max, .min, expects: 524_288.0)
    testMULCase(.max, .max, expects: -1_048_576.0)

    // These numbers are mostly randomly generated. Not some clever combination
    // that maximizes coverage of interesting values.
    testMULCase(0.0, 0.546875, expects: 0.0)
    testMULCase(0.546875, 0.0, expects: 0.0)
    testMULCase(1.078125, 1.609375, expects: 1.734375)
    testMULCase(1.609375, 1.078125, expects: 1.734375)
    testMULCase(-1.078125, 1.609375, expects: -1.734375)
    testMULCase(1.078125, -1.609375, expects: -1.734375)
    testMULCase(-1.078125, -1.609375, expects: 1.734375)
    testMULCase(3.984375, 3.984375, expects: 15.875)
    testMULCase(3.75, 3.4375, expects: 12.890625)
    testMULCase(768.0, 1.0, expects: 768.0)
    testMULCase(768.0, 891.75, expects: 684_864.0)
    testMULCase(-453_287.515625, 25_504_928.6875, expects: -20_433_077.671875)
    testMULCase(-3_782_822.296875, 4_708_357.203125, expects: 15_222_558.734375)
    testMULCase(18_622_405.171875, 8_055_470.75, expects: -28_747_760.21875)
    testMULCase(18_026_041.59375, 1_681_876.328125, expects: 2_483_636.765625)
    testMULCase(-6_006_838.90625, -24_962_378.125, expects: 25_399_917.921875)
  }

  @Test func testMUL_tooFewStackElements() {
    runStackUnderflowTests(opcode: .MUL, parameters: 2)
  }

  // MARK: - ABS 0x64
  /*
   Pops a 26.6 fixed point number, n, off the stack and pushes the absolute value of n onto the stack.
   */

  @Test func testABS_positive() {
    let val = Int32(45)
    var instance = getInstance()
    instance.run(instructions: .pushInt32(val), .ABS)

    instance.expectedEngineState.stack = [45]
    instance.validate()
  }

  @Test func testABS_negative() {
    let val = Int32(-45)
    var instance = getInstance()
    instance.run(instructions: .pushInt32(val), .ABS)

    instance.expectedEngineState.stack = [45]
    instance.validate()
  }

  @Test func testABS_min() {
    var instance = getInstance()
    instance.run(instructions: .pushInt32(.min), .ABS)

    instance.expectedEngineState.stack = [-2_147_483_648]
    instance.validate()
  }

  @Test func testABS_emptyStack() {
    runStackUnderflowTests(opcode: .ABS, parameters: 1)
  }

  // MARK: - NEG 0x65
  /*
   Negates the number at the top of the stack.
   Pops a number, n, from the stack and pushes the negated value of n onto the stack.
   */

  @Test func testNEG() {
    let val: UInt8 = 0x45
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([val]), .NEG])

    instance.expectedEngineState.stack = [-Int32(val)]
    instance.validate()
  }

  @Test func testNEG_zero() {
    let val: UInt8 = 0x0
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([val]), .NEG])

    instance.expectedEngineState.stack = [0]
    instance.validate()
  }

  @Test func testNEG_allOnes() {
    var instance = getInstance()
    instance.run(instructions: .pushInt32(-1), .NEG)

    instance.expectedEngineState.stack = [1]
    instance.validate()
  }

  @Test func testNEG_min() {
    var instance = getInstance()
    instance.run(instructions: .pushInt32(.min), .NEG)

    instance.expectedEngineState.stack = [-2_147_483_648]
    instance.validate()
  }

  @Test func testNEG_emptyStack() {
    runStackUnderflowTests(opcode: .NEG, parameters: 1)
  }

  // MARK: - FLOOR 0x66
  /*
   Takes the floor of the value at the top of the stack.
   Pops a 26.6 fixed point number n from the stack and returns n , the greatest integer value
   less than or equal to n. Note that the floor of n, though an integer value, is expressed as
   26.6 fixed point number.
   */
  @Test func testFLOOR() {
    func testFLOORCase(_ val: F26Dot6, floor: F26Dot6) {
      var instance = getInstance()
      instance.run(instructions: .pushF26Dot6(val), .FLOOR)

      instance.expectedEngineState.stack = [floor.bitPattern]
      instance.validate()
    }

    testFLOORCase(0.0, floor: 0.0)
    testFLOORCase(0.015625, floor: 0.0)
    testFLOORCase(0.984375, floor: 0.0)
    testFLOORCase(1.0, floor: 1.0)
    testFLOORCase(1.015625, floor: 1.0)

    testFLOORCase(-0.015625, floor: -1.0)
    testFLOORCase(-0.984375, floor: -1.0)
    testFLOORCase(-1.0, floor: -1.0)
    testFLOORCase(-1.015625, floor: -2.0)
    testFLOORCase(-1.984375, floor: -2.0)
    testFLOORCase(-2.0, floor: -2.0)

    testFLOORCase(19_101_722.125, floor: 19_101_722.0)
    testFLOORCase(-27_579_286.296875, floor: -27_579_287.0)
    testFLOORCase(-2_769_266.8125, floor: -2_769_267.0)
    testFLOORCase(15_489_378.578125, floor: 15_489_378.0)
    testFLOORCase(30_709_081.875, floor: 30_709_081.0)
  }

  // MARK: - CEILING 0x67
  /*
   Takes the ceiling of the number at the top of the stack.
   Pops a number n from the stack and pushes n , the least integer value greater than or equal
   to n. Note that the ceiling of n, though an integer value, is expressed as 26.6 fixed point
   number.
   */
  @Test func testCEILING() {
    func testCEILINGCase(_ val: F26Dot6, ceiling: F26Dot6) {
      var instance = getInstance()
      instance.run(instructions: .pushF26Dot6(val), .CEILING)

      instance.expectedEngineState.stack = [ceiling.bitPattern]
      instance.validate()
    }

    testCEILINGCase(0.0, ceiling: 0.0)
    testCEILINGCase(0.015625, ceiling: 1.0)
    testCEILINGCase(0.984375, ceiling: 1.0)
    testCEILINGCase(1.0, ceiling: 1.0)
    testCEILINGCase(1.015625, ceiling: 2.0)

    testCEILINGCase(-0.015625, ceiling: 0.0)
    testCEILINGCase(-0.984375, ceiling: 0.0)
    testCEILINGCase(-1.0, ceiling: -1.0)
    testCEILINGCase(-1.015625, ceiling: -1.0)
    testCEILINGCase(-1.984375, ceiling: -1.0)
    testCEILINGCase(-2.0, ceiling: -2.0)

    testCEILINGCase(19_101_722.125, ceiling: 19_101_723.0)
    testCEILINGCase(-27_579_286.296875, ceiling: -27_579_286.0)
    testCEILINGCase(-2_769_266.8125, ceiling: -2_769_266.0)
    testCEILINGCase(15_489_378.578125, ceiling: 15_489_379.0)
    testCEILINGCase(30_709_081.875, ceiling: 30_709_082.0)
  }

  // MARK: - ROUND 0x68 - 0x6B
  @Test func testROUND_oob() {
    runNegativeTest(instructions: [.ROUND_0], failure: .stackUnderflow)
    runNegativeTest(instructions: [.ROUND_1], failure: .stackUnderflow)
    runNegativeTest(instructions: [.ROUND_2], failure: .stackUnderflow)
    runNegativeTest(instructions: [.ROUND_3], failure: .stackUnderflow)
  }

  @Test func testRoundStateReset() {
    var instance = getInstance()
    instance.run(.glyf, instructions: .setRoundState(.rthg))
    #expect(instance.engineState().variables.roundState == .rthg)
    instance.run(.glyf, instructions: [.CLEAR])
    instance.expectedEngineState.variables.roundState = .rtg
    instance.validate()
  }

  // rounded values tested with each rounding mode instruction

  // MARK: - NROUND 0x6C - 0x6F
  @Test func testNROUND() {
    let nround: [HintingInstruction] = [.NROUND_0, .NROUND_1, .NROUND_2, .NROUND_3]
    runRoundingTest(roundingMode: .roff, roundInstructions: nround) { $0 }
    runRoundingTest(roundingMode: .rdtg, roundInstructions: nround) { $0 }
    runRoundingTest(roundingMode: .rutg, roundInstructions: nround) { $0 }
    runRoundingTest(roundingMode: .rtg, roundInstructions: nround) { $0 }
    runRoundingTest(roundingMode: .rthg, roundInstructions: nround) { $0 }
    runRoundingTest(roundingMode: .rtdg, roundInstructions: nround) { $0 }
    let sround = RoundState(superRoundParameter: 0)
    runRoundingTest(roundingMode: sround, roundInstructions: nround) { $0 }
    let s45round = RoundState(super45RoundParameter: 0)
    runRoundingTest(roundingMode: s45round, roundInstructions: nround) { $0 }
  }

  @Test func testNROUND_oob() {
    runNegativeTest(instructions: [.NROUND_0], failure: .stackUnderflow)
    runNegativeTest(instructions: [.NROUND_1], failure: .stackUnderflow)
    runNegativeTest(instructions: [.NROUND_2], failure: .stackUnderflow)
    runNegativeTest(instructions: [.NROUND_3], failure: .stackUnderflow)
  }

  // MARK: - WCVTF 0x70
  /*
   Writes a scaled F26Dot6 value to the specified control value table location.

   Pops an integer value, n, and a control value table location l from the stack. The FUnit
   value is scaled to the current point size and resolution and put in the control value table.
   This instruction assumes the value is expressed in FUnits and not pixels.

   Since the CVT has been scaled to pixel values, the value taken from the stack is scaled to
   the appropriate pixel value before being written to the table.
   */

  @Test func testWCVTF() {
    let value = F26Dot6(1.5)

    var instance = getInstance()
    instance.run(.prep, instructions: [.NPUSHB([1, UInt8(value.bitPattern)]), .WCVTF])

    instance.expectedEngineState.cvt[1] = 24.0
    instance.validate()
  }

  // bincompat: in FPGM CPP writes the value to CVT and only ever reads 0.
  @Test func testWCVTF_fpgm() {
    let location: UInt8 = 0x01
    let byte: UInt8 = 0x60
    let testVector = FixedVector<F2Dot14>.normalizing(x: 1, y: 0.5)
    var instance = getInstance()

    instance.run(
      .fpgm,
      instructions: [
        .PUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SPVFS,
        .PUSHB([location, byte]), .WCVTF,
        .PUSHB([location]), .RCVT,
      ]
    )
    instance.expectedEngineState.cvt[Int(location)] = 0
    instance.expectedEngineState.stack = [0]
    instance.expectedEngineState.variables.projectionVector = testVector
    instance.validate()
  }

  @Test func testWCVTF_stretchedWide() {
    var instance = getInstance()
    let testVector = FixedVector<F2Dot14>.normalizing(x: 1, y: 0.5)
    let value = F26Dot6(0.78125)
    instance.setScaleFactors(yStretch: 256)
    instance.run(
      .prep,
      instructions: [
        .PUSHW([testVector.x.bitPattern, testVector.y.bitPattern]), .SPVFS,
        .PUSHB([2, UInt8(value.bitPattern)]), .WCVTF,

          .SPVTCA_Y, .PUSHB([0, UInt8(value.bitPattern)]), .WCVTF,

          .SPVTCA_X, .PUSHB([1, UInt8(value.bitPattern)]), .WCVTF,
      ]
    )
    instance.expectedEngineState.cvt[0] = 12.5
    instance.expectedEngineState.cvt[1] = 12.5
    instance.expectedEngineState.cvt[2] = 12.5
    instance.validate()
  }

  @Test func testWCVTF_OOB() {
    runNegativeTest(.fpgm, instructions: .PUSHW([1_024, 50]), .WCVTF, failure: .cvtLocationOutOfBounds)
    runNegativeTest(.prep, instructions: .PUSHW([1_024, 50]), .WCVTF, failure: .cvtLocationOutOfBounds)
    runNegativeTest(.glyf, instructions: .PUSHW([1_024, 50]), .WCVTF, failure: .cvtLocationOutOfBounds)
  }

  @Test func testWCVTF_tooFewStackElements() {
    runStackUnderflowTests(opcode: .WCVTF, parameters: 2)
  }

  // MARK: - DELTAP2, DELTAP3 0x71, 0x72
  // see DELTAC tests for edge case tests; DELTAP and DELTAC share their
  // implementation
  @Test func testDELTAP2() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: 2, y: 2),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(487), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(1),
        .pushInt32(1), .DELTAP2,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 487
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2.125, y: 2, xMoved: true)
    instance.validate()
  }

  @Test func testDELTAP3() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [
        OutlinePoint(x: 1, y: 1),
        OutlinePoint(x: 2, y: 2),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(471), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(1),
        .pushInt32(1), .DELTAP3,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 471
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 2.125, y: 2, xMoved: true)
    instance.validate()
  }

  // MARK: - DELTAC1, DELTAC2, DELTAC3 0x73-0x75
  @Test func testDELTAC1_emptyStack() {
    runNegativeTest(instructions: [.DELTAC1], failure: .stackUnderflow)
  }

  @Test func testDELTAC1_stackUnderflow() {
    runNegativeTest(.notFpgm(), instructions: [.pushInt32(1), .DELTAC1], failure: .stackUnderflow)
  }

  @Test func testDELTAC1_fpgm() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .fpgm,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(487), .SDB,
        .pushInt32(9 << 4 | 15), .pushInt32(11),
        .pushInt32(1), .DELTAC2,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 487
    instance.validate()
  }

  @Test func testDELTAC1_0_pairs() {
    var instance = getInstance()
    instance.run(.notFpgm(), instructions: [.pushInt32(0), .DELTAC1])
    instance.validate()
  }

  @Test func testDELTAC1_32BitOverflowPairsNotWithinRange() {
    var instance = getInstance()
    instance.run(.notFpgm(), instructions: [.pushInt32(.max), .DELTAC1])
    instance.validate()
  }

  @Test func testDELTAC1_32BitOverflowPairs() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(503), .SDB,
        .pushInt32(.max), .DELTAC1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.validate()
  }

  @Test func testDELTAC1_negative_pairs() {
    var instance = getInstance()
    instance.setScaleFactors(xStretch: 16, yStretch: 16)
    instance.run(
      .notFpgm(),
      instructions: [
        .NPUSHB(.init(repeating: 42, count: 255)),
        // This value is 1: negative and 2: smaller than the stack when shifted << 1
        .pushInt32(.init(bitPattern: 0x8000_007f)),
        .DELTAC1,
      ]
    )
    instance.expectedEngineState.stack = .init(repeating: 42, count: 255)
    instance.validate()
  }

  @Test func testDELTAC1_1pair_ppemOutOfRange() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(0), .pushInt32(10),
        .pushInt32(1), .DELTAC1,
      ]
    )
    instance.validate()
  }

  @Test func testDELTAC1_3pairs_allTooLow() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(503), .SDB,
        .pushInt32(6 << 4), .pushInt32(10),
        .pushInt32(7 << 4), .pushInt32(10),
        .pushInt32(8 << 4), .pushInt32(10),
        .pushInt32(3), .DELTAC1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.validate()
  }

  @Test func testDELTAC1_3pairs_allTooHigh() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(503), .SDB,
        .pushInt32(10 << 4), .pushInt32(10),
        .pushInt32(11 << 4), .pushInt32(10),
        .pushInt32(12 << 4), .pushInt32(10),
        .pushInt32(3), .DELTAC1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.validate()
  }

  @Test func testDELTAC1_3pairs_firstIsTarget() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(503), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(9),
        .pushInt32(10 << 4 | 8), .pushInt32(10),
        .pushInt32(11 << 4 | 8), .pushInt32(11),
        .pushInt32(3), .DELTAC1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.cvt[9] = 0.125
    instance.validate()
  }

  @Test func testDELTAC1_3pairs_lastIsTarget() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(503), .SDB,
        .pushInt32(7 << 4 | 8), .pushInt32(10),
        .pushInt32(8 << 4 | 8), .pushInt32(11),
        .pushInt32(9 << 4 | 8), .pushInt32(9),
        .pushInt32(3), .DELTAC1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.cvt[9] = 0.125
    instance.validate()
  }

  @Test func testDELTAC1_3pairs_twoTargets() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(503), .SDB,
        .pushInt32(7 << 4 | 8), .pushInt32(10),
        .pushInt32(9 << 4 | 8), .pushInt32(11),
        .pushInt32(9 << 4 | 8), .pushInt32(9),
        .pushInt32(3), .DELTAC1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.cvt[9] = 0.125
    instance.expectedEngineState.cvt[11] = 0.125
    instance.validate()
  }

  @Test func testDELTAC1_6pairs_notSorted() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(503), .SDB,
        .pushInt32(7 << 4 | 8), .pushInt32(9),
        .pushInt32(8 << 4 | 8), .pushInt32(10),
        .pushInt32(9 << 4 | 8), .pushInt32(11),
        .pushInt32(7 << 4 | 8), .pushInt32(12),
        .pushInt32(8 << 4 | 8), .pushInt32(13),
        .pushInt32(9 << 4 | 8), .pushInt32(14),
        .pushInt32(6), .DELTAC1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.cvt[14] = 0.125
    instance.validate()
  }

  @Test func testDELTAC1_8pairs_notSorted_inTheMiddleAndAtEnd() {
    var instance = getInstance()
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(503), .SDB,
        .pushInt32(5 << 4 | 8), .pushInt32(7),
        .pushInt32(6 << 4 | 8), .pushInt32(8),
        .pushInt32(7 << 4 | 8), .pushInt32(9),
        .pushInt32(8 << 4 | 8), .pushInt32(10),
        .pushInt32(9 << 4 | 8), .pushInt32(11),
        .pushInt32(10 << 4 | 8), .pushInt32(12),
        .pushInt32(8 << 4 | 8), .pushInt32(13),
        .pushInt32(9 << 4 | 8), .pushInt32(14),
        .pushInt32(8), .DELTAC1,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 503
    instance.expectedEngineState.cvt[11] = 0.125
    instance.validate()
  }

  @Test func testDELTAC1_modmin() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(487), .SDB,
        .pushInt32(9 << 4 | 0), .pushInt32(11),
        .pushInt32(1), .DELTAC2,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 487
    instance.expectedEngineState.cvt[11] = -1
    instance.validate()
  }

  @Test func testDELTAC1_modmax() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(487), .SDB,
        .pushInt32(9 << 4 | 15), .pushInt32(11),
        .pushInt32(1), .DELTAC2,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 487
    instance.expectedEngineState.cvt[11] = 1
    instance.validate()
  }

  @Test func testDELTAC2() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(487), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(11),
        .pushInt32(1), .DELTAC2,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 487
    instance.expectedEngineState.cvt[11] = 0.125
    instance.validate()
  }

  @Test func testDELTAC3() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.run(
      .notFpgm(),
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(471), .SDB,
        .pushInt32(9 << 4 | 8), .pushInt32(11),
        .pushInt32(1), .DELTAC3,
      ]
    )
    instance.expectedEngineState.variables.deltaBase = 471
    instance.expectedEngineState.cvt[11] = 0.125
    instance.validate()
  }

  // MARK: - SROUND 0x76
  @Test(arguments: 0..<256)
  func testSROUND_state(parameter: Int) {
    let sround = RoundState(superRoundParameter: UInt8(parameter))
    var instance = getInstance()
    instance.run(instructions: .setRoundState(sround))
    instance.expectedEngineState.variables.roundState = sround
    instance.validate()
  }

  @Test(arguments: 0..<256)
  func testSROUND_rounding(parameter: Int) {
    let sround = RoundState(superRoundParameter: UInt8(parameter))
    let expected = SuperRoundReferenceData.sroundExpected[parameter]
    runRoundingTest(roundingMode: sround) { index, _ in
      F26Dot6(bitPattern: expected[index])
    }
  }

  // MARK: - S45ROUND 0x77
  @Test(arguments: 0..<192)
  func testS45ROUND_state(parameter: Int) {
    let sround45 = RoundState(super45RoundParameter: UInt8(parameter))
    var instance = getInstance()
    instance.run(instructions: .setRoundState(sround45))
    instance.expectedEngineState.variables.roundState = sround45
    instance.validate()
  }

  @Test(arguments: 0..<256)
  func testS45ROUND_rounding(parameter: Int) {
    let sround45 = RoundState(super45RoundParameter: UInt8(parameter))
    let expected = SuperRoundReferenceData.s45roundExpected[parameter]
    runRoundingTest(roundingMode: sround45, testNumbers: SuperRoundReferenceData.s45roundTestNumbers) { index, _ in
      F26Dot6(bitPattern: expected[index])
    }
  }

  /// Verify that S45ROUND doesn't trap on overflow-sensitive inputs.
  /// The C++ interpreter mishandles fixed-point overflow for these values, so we can't
  /// compare against C++ reference data — but we still verify the Swift implementation
  /// handles them without trapping.
  @Test(arguments: 0..<256)
  func testS45ROUND_overflowSafety(parameter: Int) {
    let sround45 = RoundState(super45RoundParameter: UInt8(parameter))
    let overflowInputs: [F26Dot6] = [
      .min,
      -23_726_566.40625,
      -11_863_283.203125,
      +11_863_283.203125,
      +23_726_566.40625,
      .max,
    ]
    for value in overflowInputs {
      // Must not trap; result is not checked against C++ (which overflows here).
      _ = sround45.round(value)
    }
  }

  // MARK: - ROFF 0x7a
  @Test func testROFF_state() {
    var instance = getInstance()
    instance.run(instructions: .setRoundState(.roff))
    instance.expectedEngineState.variables.roundState = .roff
    instance.validate()
  }

  @Test func testROFF_rounding() {
    runRoundingTest(roundingMode: .roff) { $0 }
  }

  // MARK: - RUTG 0x7c
  @Test func testRUTG_state() {
    var instance = getInstance()
    instance.run(instructions: .setRoundState(.rutg))
    instance.expectedEngineState.variables.roundState = .rutg
    instance.validate()
  }

  @Test func testRUTG_rounding() {
    runRoundingTest(roundingMode: .rutg) { value in
      value.roundingIfRepresentable(.awayFromZero) ?? 0
    }
  }

  // MARK: - RDTG 0x7d
  func testRDTG_state() {
    var instance = getInstance()
    instance.run(instructions: .setRoundState(.rdtg))
    instance.expectedEngineState.variables.roundState = .rdtg
    instance.validate()
  }

  func testRDTG_rounding() {
    runRoundingTest(roundingMode: .rdtg) { value in
      value.roundingIfRepresentable(.towardZero) ?? 0
    }
  }

  // MARK: - JROT 0x78
  /*
   Moves the instruction pointer to a new location specified by the offset popped from the stack
   if the element tested has a FALSE (zero) value.
   */

  @Test func testJROT_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 5, 2]),
      .JROT,  // pops condition 2 and offset 5
      .CLEAR,  // jumped over!
      .NPUSHB([42]),  // jumped over!
      .DUP,  // executed!
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [1, 1]
    instance.validate()
  }

  @Test func testJROT_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 5, 0]),
      .JROT,  // pops condition 0 and offset 5
      .CLEAR,  // executed!
      .NPUSHB([42]),  // executed!
      .DUP,  // executed!
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [42, 42]
    instance.validate()
  }

  @Test func testJROT_backwards() {
    var instance = getInstance()
    instance.setStorageValue(9, at: 7)

    let instructions: [HintingInstruction] = [
      // setup stack to jump back
      .PUSHB([16]),
      .pushInt32(-7),
      .PUSHB([0]),
      .pushInt32(-7),
      .PUSHB([1]),

      // loop back over this code
      .PUSHB([7, 7]),
      .RS,  // push storage index 7 onto stack
      .DUP,
      .ADD,
      .WS,  // write shifted storage value back to index 7

      // pops condition 1 and offset -7. then when we come back, pops condition 0 and offset -7.
      // thus, we loop once and execute the above code twice
        .JROT,
      .DUP,
    ]

    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [16, 16]
    instance.expectedEngineState.storage[7] = 36

    instance.validate()
  }

  @Test func testJROT_outOfBounds_backwards() {
    runNegativeTest(
      instructions: .PUSHB([0, 8]),
      .SUB,
      .PUSHB([1]),
      .JROT,
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testJROT_taken_end() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 5, 2]),
      .JROT,  // pops condition 2 and offset 5
      .CLEAR,  // jumped over!
      .NPUSHB([42]),  // jumped over!
      // lands here
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [1]
    instance.validate()
  }

  @Test func testJROT_forwardOutOfBounds() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 2, 9, 1]),
      .JROT,
      .CLEAR,  // jumped over
    ]

    instance.run(instructions: instructions, failure: .ranOffEndOfInstructions)
    instance.validate(except: .stack)
  }

  @Test func testJROT_forwardErrorOutOfBounds() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([1, 2]),
      .pushInt32(.init(UInt16.max) * 3),
      .PUSHB([3]),
      .JROT,
      .CLEAR,  // jumped over
    ]

    instance.run(instructions: instructions, failure: .ranOffEndOfInstructions)
    instance.validate(except: .stack)
  }

  @Test func testJROT_stackUnderflow() {
    runNegativeTest(instructions: .JROT, failure: .stackUnderflow)

    runNegativeTest(
      instructions: .PUSHB([1]),
      .JROT,
      failure: .stackUnderflow
    )
  }

  // MARK: - JROF 0x79
  /*
   Moves the instruction pointer to a new location specified by the offset popped from the stack
   if the element tested has a FALSE (zero) value.
   */

  @Test func testJROF_taken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 5, 0]),
      .JROF,  // pops condition 0 and offset 5
      .CLEAR,  // jumped over!
      .NPUSHB([42]),  // jumped over!
      .DUP,  // executed!
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [1, 1]
    instance.validate()
  }

  @Test func testJROF_notTaken() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 5, 2]),
      .JROF,  // pops condition 2 and offset 5
      .CLEAR,  // executed!
      .NPUSHB([42]),  // executed!
      .DUP,  // executed!
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [42, 42]
    instance.validate()
  }

  @Test func testJROF_backwards() {
    var instance = getInstance()

    // Execute a loop twice, once starting with non-zero on the
    // stack, once with a zero on the stack. Each time through the
    // loop, the stack value is NOT'ed. So the loop will end with
    // 1 on the stack. We start with a non-zero value that isn't 1,
    // so ending up with 1 proves that we ran the loop twice.
    let instructions: [HintingInstruction] = [
      .NPUSHB([5]),  // [5]
      // [5]			| [0]
        .NOT,  // [0]			| [1]
      .DUP,  // [0, 0]		| [1, 1]
      .NPUSHB([7]),  // [7, 0, 0]	| [7, 1, 1]
      .NEG,  // [-7, 0, 0]	| [-7, 1, 1]
      .SWAP,  // [0, 7, 0]	| [1, -7, 1]
      .JROF,  // [0]			| [1]
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [1]
    instance.validate()
  }

  @Test func testJROF_outOfBounds_backwards() {
    runNegativeTest(
      instructions: .PUSHB([0, 8]),
      .SUB,
      .PUSHB([0]),
      .JROF,
      failure: .ranOffEndOfInstructions
    )
  }

  @Test func testJROF_taken_end() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 5, 0]),
      .JROF,  // pops condition 0 and offset 5
      .CLEAR,  // jumped over!
      .NPUSHB([42]),  // 1 + 1 + 1 bytes jumped over!
      // lands at end!
    ]
    instance.run(instructions: instructions)

    instance.expectedEngineState.stack = [1]
    instance.validate()
  }

  @Test func testJROF_forwardOutOfBounds() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .NPUSHB([1, 2, 9, 0]),
      .JROF,
      .CLEAR,  // jumped over
    ]

    instance.run(instructions: instructions, failure: .ranOffEndOfInstructions)
    instance.validate(except: .stack)
  }

  @Test func testJROF_forwardErrorOutOfBounds() {
    var instance = getInstance()
    let instructions: [HintingInstruction] = [
      .PUSHB([1, 2]),
      .pushInt32(.init(UInt16.max) * 3),
      .PUSHB([0]),
      .JROF,
      .CLEAR,  // jumped over
    ]

    instance.run(instructions: instructions, failure: .ranOffEndOfInstructions)
    instance.validate(except: .stack)
  }

  @Test func testJROF_stackUnderflow() {
    runNegativeTest(instructions: .JROF, failure: .stackUnderflow)

    runNegativeTest(
      instructions: .PUSHB([0]),
      .JROF,
      failure: .stackUnderflow
    )
  }

  // MARK: - (undefined but reserved) 0x7b

  @Test func test0x7b_isIllegal() {
    runNegativeTest(instructions: .literal(0x7b), failure: .illegalInstruction)
  }

  // `.illegalInstruction` is indistinguishable from an undefined opcode, make sure we didn't call the idef call handler
  @Test func test0x7b_isUnPatchable() {
    runNegativeTest(
      .notGlyf(),
      instructions: .PUSHB([0x7b]),
      .IDEF,
      .PUSHB([0xff]),
      .ENDF,
      .literal(0x7b),
      failure: .illegalInstruction
    )
  }

  // MARK: - SANGW 0x7e
  /*
   Pops a 32 bit integer, weight, from the stack and sets the value of the angle weight state
   variable accordingly. This instruction is anachronistic. Except for popping a single stack
   element, it has no effect.
   */

  @Test func testSANGW() {
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([2]), .SANGW])
    instance.validate()
  }

  @Test func testSANGW_emptyStack() {
    runStackUnderflowTests(opcode: .SANGW, parameters: 1)
  }

  // MARK: - AA 0x7f
  /*
   Pops one argument from the stack. This instruction is anachronistic and has no other effect.
   */

  @Test func testAA() {
    var instance = getInstance()
    instance.run(instructions: [.NPUSHB([2]), .AA])
    instance.validate()
  }

  @Test func testAA_emptyStack() {
    runStackUnderflowTests(opcode: .AA, parameters: 1)
  }

  // MARK: - FLIPPT 0x80
  /*
   Makes an on-curve point an off-curve point or an off-curve point an on-curve point.
   Pops points, p, p1, p2, , ploopvalue from the stack. If pi is an on-curve point it is made an
   off-curve point. If pi is an off-curve point it is made an on-curve point. None of the points
   pi is marked as touched. As a result, none of the flipped points will be affected by an
   IUP[ ] instruction. A FLIPPT[ ] instruction redefines the shape of a glyph outline.
   */
  @Test func testFLIPPT_flip() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 1))
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(.glyf, instructions: [.pushInt32(0), .FLIPPT])
    instance.expectedEngineState.glyphPoints[point: 0].onCurve = true
    instance.validate()
  }

  @Test func testFLIPPT_toomany() {
    runNegativeTest(
      .glyf,
      instructions: [
        .setPoint(.zero, at: 0, in: .glyph),
        .pushInt32(3),
        .SLOOP,
        .pushInt32(0),
        .FLIPPT,
      ],
      expectingProperties: [
        .stack([0]),
        .variable(\.loop, 3),
        .glyphPoint(.init(scaled: .zero, onCurve: true, xMoved: true, yMoved: true), at: 0),
      ],
      failure: .stackUnderflow
    )
  }

  @Test func testFLIPPT_pedanticZoneChecks1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(.glyf, instructions: .FLIPPT, failure: .maxpLimitExceeded)
    instance.validate()
  }

  // MARK: - FLIPRGON, FLIPRGOFF 0x81, 0x82
  @Test func testFLIPRGON_0stack() {
    runNegativeTest(.glyf, instructions: .FLIPRGON, failure: .stackUnderflow)
  }

  @Test func testFLIPRGON_1stack() {
    runNegativeTest(
      .glyf,
      instructions: .pushInt32(1),
      .FLIPRGON,
      exemptingProperties: .stack,
      failure: .stackUnderflow
    )
  }

  @Test func testFLIPRGON_2stack_minTooLow() {
    runNegativeTest(
      .glyf,
      glyphPoints: [OutlinePoint(x: 0, y: 0), OutlinePoint(x: 0, y: 0)],
      instructions: [.pushInt32(1), .SZP0, .pushInt32(-1), .pushInt32(1), .FLIPRGON],
      expectingProperties: [.variable(\.zp0, .glyph)],
      exemptingProperties: .stack,
      failure: .invalidOperand
    )
  }

  @Test func testFLIPRGON_2stack_maxTooHigh() {
    runNegativeTest(
      .glyf,
      glyphPoints: [.zero, .zero],
      instructions: [.pushInt32(1), .SZP0, .pushInt32(0), .pushInt32(10), .FLIPRGON],
      expectingProperties: [.variable(\.zp0, .glyph)],
      exemptingProperties: .stack,
      failure: .invalidOperand
    )
  }

  @Test func testFLIPRGON_2stack_maxBelowMin() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints([OutlinePoint(x: 0, y: 0), OutlinePoint(x: 0, y: 0)], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(1), .pushInt32(0),
        .FLIPRGON,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.validate()
  }

  @Test func testFLIPRGON_1() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints([OutlinePoint(x: 0, y: 0), OutlinePoint(x: 0, y: 0)], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(1), .pushInt32(1),
        .FLIPRGON,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.glyphPoints[point: 1] = OutlinePoint(x: 0, y: 0, onCurve: true)
    instance.validate()
  }

  @Test func testFLIPRGON_2() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints([OutlinePoint(x: 0, y: 0), OutlinePoint(x: 0, y: 0)], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(0), .pushInt32(1),
        .FLIPRGON,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.glyphPoints[point: 0] = OutlinePoint(x: 0, y: 0, onCurve: true)
    instance.expectedEngineState.glyphPoints[point: 1] = OutlinePoint(x: 0, y: 0, onCurve: true)
    instance.validate()
  }

  @Test func testFLIPRGON_pedanticZoneChecks1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(.glyf, instructions: .FLIPRGON, failure: .maxpLimitExceeded)
    instance.validate()
  }

  @Test func testFLIPRGOFF_1() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [OutlinePoint(x: 0, y: 0, onCurve: true), OutlinePoint(x: 0, y: 0, onCurve: true)],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(1), .pushInt32(1),
        .FLIPRGOFF,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.glyphPoints[point: 1] = OutlinePoint(x: 0, y: 0, onCurve: false)
    instance.validate()
  }

  @Test func testFLIPRGOFF_2() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(
      [OutlinePoint(x: 0, y: 0, onCurve: true), OutlinePoint(x: 0, y: 0, onCurve: true)],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1), .SZP0,
        .pushInt32(0), .pushInt32(1),
        .FLIPRGOFF,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.glyphPoints[point: 0] = OutlinePoint(x: 0, y: 0, onCurve: false)
    instance.expectedEngineState.glyphPoints[point: 1] = OutlinePoint(x: 0, y: 0, onCurve: false)
    instance.validate()
  }

  @Test func testFLIPRGOFF_pedanticZoneChecks1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(.glyf, instructions: .FLIPRGOFF, failure: .maxpLimitExceeded)
    instance.validate()
  }

  // MARK: - SCANCTRL 0x85
  @Test func testSCANCTRL() {
    var instance = getInstance()
    instance.run(instructions: [.pushInt32(5), .SCANCTRL])
    instance.expectedEngineState.variables.scanControl = .init(rawValue: 5)
    instance.validate()
  }

  @Test func testSCANCTRl_underflow() {
    runStackUnderflowTests(opcode: .SCANCTRL, parameters: 1)
  }

  @Test func testSCANCTRL_bincompat_allBits() {
    var instance = getInstance()
    instance.run(.glyf, instructions: [.pushInt32(0x7fff_ffff), .SCANCTRL])
    instance.expectedEngineState.variables.scanControl = .init(rawValue: 0x7fff_ffff)
    instance.validate()
  }

  @Test func testSCANCTRL_bincompat_selective() {
    var instance = getInstance()
    instance.run(.glyf, instructions: [.pushInt32(0x1000_1234), .PUSHB([1]), .SCANTYPE, .SCANCTRL])
    instance.expectedEngineState.variables.scanControl = .init(rawValue: 0x1001_1234)
    instance.validate()
  }

  @Test func testSCANCTRL_bincompat_restoredBySCANTYPE() {
    var instance = getInstance()
    instance.run(.glyf, instructions: [.PUSHB([1]), .pushInt32(0x7fff_1234), .SCANCTRL, .SCANTYPE])
    instance.expectedEngineState.variables.scanControl = .init(rawValue: 0x0001_1234)
    instance.validate()
  }

  // MARK: - SDPVTL[a] 0x86,0x87
  /*
   Sets a second projection vector based upon the original position of two points. The new
   vector will point in a direction that is parallel to the line defined from p2 to p1. The
   projection vector is also set in in a direction that is parallel to the line from p2 to p1
   but it is set using the current position of those points.
   Pops two point numbers from the stack and uses them to specify a line that defines a second,
   dual projection vector. This dual projection vector uses coordinates from the original
   outline before any instructions are executed. It is used only with the IP[], GC[], MD[],
   MDRP[] and MIRP[] instructions. The dual projection vector is used in place of the projection
   vector in these instructions. This continues until some instruction sets the projection
   vector again.
   */

  @Test func testSDPVTL_0() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 2))
    let op1 = OutlineCoord(x: -1, y: 2)
    let op2 = OutlineCoord(x: 1, y: 1)

    instance.run(
      .prep,
      instructions: [
        // Setting to the twilight zone so the scaled/unhinted is also set
        .setPoint(op1, at: 0, in: .twilight),
        .setPoint(op2, at: 1, in: .twilight),
        // Change the hinted coordinates of the twilight points
        .PUSHB([0]), .SZPS, .SVTCA_X, .PUSHB([0, 1]), .ALIGNPTS,
        // Now the projection vector and dual projection vector should wind up with different values
        .PUSHB([0]), .SZPS, .PUSHB([0, 1]), .SDPVTL_0,
        // Restore zone pointers back to .glyph
        .PUSHB([1]), .SZPS,
      ]
    )

    // x : -0.8944091796875, y: 0.44720458984375, for whatever that's worth
    instance.expectedEngineState.variables.dualProjectionVector = .init(
      x: .init(bitPattern: -14_654),
      y: .init(bitPattern: 7_327)
    )
    instance.expectedEngineState.variables.projectionVector = .init(x: 0, y: 1)
    instance.validate(except: .points)
  }

  @Test func testSDPVTL_1() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxTwilightPoints: 2))
    let op1 = OutlineCoord(x: -1, y: 2)
    let op2 = OutlineCoord(x: 1, y: 1)

    instance.run(
      .prep,
      instructions: [
        // Setting to the twilight zone so the scaled/unhinted is also set
        .setPoint(op1, at: 0, in: .twilight),
        .setPoint(op2, at: 1, in: .twilight),
        // Change the hinted coordinates of the twilight points
        .PUSHB([0]), .SZPS, .SVTCA_X, .PUSHB([0, 1]), .ALIGNPTS,
        // Now the projection vector and dual projection vector should wind up with different values
        .PUSHB([0]), .SZPS, .PUSHB([0, 1]), .SDPVTL_1,
        // Restore zone pointers back to .glyph
        .PUSHB([1]), .SZPS,
      ]
    )

    // x : -0.8944091796875, y: 0.44720458984375, for whatever that's worth
    instance.expectedEngineState.variables.dualProjectionVector = .init(
      x: .init(bitPattern: -7_327),
      y: .init(bitPattern: -14_654)
    )
    instance.expectedEngineState.variables.projectionVector = .init(x: -1, y: 0)
    instance.validate(except: .points)
  }

  @Test func testSDPVTL_OOB() {
    runNegativeTest(.glyf, instructions: .PUSHB([99, 0]), .SDPVTL_0, failure: .noSuchPoint)
    runNegativeTest(.glyf, instructions: .PUSHB([99, 0]), .SDPVTL_1, failure: .noSuchPoint)

    runNegativeTest(.glyf, instructions: .PUSHB([0, 99]), .SDPVTL_0, failure: .noSuchPoint)
    runNegativeTest(.glyf, instructions: .PUSHB([0, 99]), .SDPVTL_1, failure: .noSuchPoint)
  }

  @Test func testSDPVTL_tooFewStackElements() {
    runStackUnderflowTests(.glyf, opcode: .SDPVTL_0, parameters: 2)
    runStackUnderflowTests(.glyf, opcode: .SDPVTL_1, parameters: 2)
  }

  @Test func testSDPVTL_pedanticZoneChecks() {
    var instance = getInstance(maxp: sfntMaxProfileTable(maxPoints: 2))
    instance.setPoints([.zero, .zero, .zero, .zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 1]), .SDPVTL_1,
      ],
      failure: .maxpLimitExceeded
    )
    instance.validate()
  }

  // MARK: - GETINFO 0x88
  /*
   Used to obtain data about the version of the TrueType engine that is rendering the font as
   well as the characteristics of the current glyph.
   */

  @Test func testGETINFO() {
    for (rotated, stretched) in (0..<4).map({ ($0 & 1 != 0, $0 & 2 != 0) }) {
      for selector in 0...0x10 {
        var instance = getInstance()
        instance.setScaleFactors(yStretch: stretched ? 256 : 512, isRotated: rotated, isStretched: stretched)
        instance.run(.glyf, instructions: .PUSHB([UInt8(selector)]), .GETINFO)
        var result = Int32(0)
        if selector & (1 << 0) != 0 { result |= 7 }
        if selector & (1 << 1) != 0, rotated { result |= 1 << 8 }
        if selector & (1 << 2) != 0, stretched { result |= 1 << 9 }
        // Reference interpreter unconditionally claims variations and vertical metrics when asked
        if selector & (1 << 3) != 0 { result |= 1 << 10 }
        if selector & (1 << 4) != 0 { result |= 1 << 11 }
        instance.expectedEngineState.stack = [result]
        instance.validate()
      }
    }
  }

  @Test func testGETINFO_invalidSelector() {
    var instance = getInstance()
    let selector = Int32.random(in: 0 ... .max)
    instance.run(.glyf, instructions: .pushInt32(selector), .GETINFO)
    var result = Int32(0)
    if selector & 0x1 != 0 { result |= 7 }
    if selector & 0x8 != 0 { result |= 1 << 10 }
    if selector & 0x10 != 0 { result |= 1 << 11 }
    instance.expectedEngineState.stack = [result]
    instance.validate()
  }

  @Test func testGETINFO_tooFewStackElements() {
    runStackUnderflowTests(opcode: .GETINFO, parameters: 1)
  }

  // MARK: - IDEF 0x89

  /*
   Begins the definition of an instruction. The instruction is identified by the opcode popped.
   The intent of the IDEF[ ] instruction is to allow old versions of the scaler to work with
   fonts that use instructions defined in later releases of the TrueType interpreter.
   Referencing an undefined opcode will have no effect. The IDEF[ ] is not intended for creating
   user defined instructions. The FDEF[ ] should be used for that purpose.
   The instruction definition that began with the IDEF[ ] terminates when an ENDF[ ] is
   encountered in the instruction stream. Nested IDEFs are not allowed. Subsequent executions of
   the opcode popped will be directed to the contents of this instruction definition. IDEFs
   should be defined in the font program. Defining instructions in the CVT program is not
   recommended.
   */

  // Note: 0x91 patching is also tested by `testGETVARIATION_empty` and `testGETVARIATION_empty_definedIDEF`
  @Test func testIDEF_allPatchableOpcodes() {
    let ideffable: [UInt8] = [
      0x28, 0x83, 0x84, 0x8f, 0x90, 0x91, 0x93, 0x94, 0x95, 0x96, 0x97, 0x98,
      0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f, 0xa0, 0xa1, 0xa2, 0xa3, 0xa4,
      0xa5, 0xa6, 0xa7, 0xa8, 0xa9, 0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf,
    ]

    for opcode in ideffable {
      runNegativeTest(instructions: .literal(opcode), failure: .illegalInstruction)

      var instance = getInstance()
      instance.run(.notGlyf(), instructions: .PUSHB([opcode]), .IDEF, .PUSHB([opcode]), .ENDF, .literal(opcode))
      instance.expectedEngineState.stack = [Int32(opcode)]
      instance.validate()
    }
  }

  /// idef only patches unused opcodes so we'd expect a redefinition not to cause any functional change
  @Test func testIDEF_redefineExistingOpcode() {
    var instance = getInstance(maxp: .init(maxInstructionDefs: 1))

    instance.run(.notGlyf(), instructions: .PUSHB([0x99, 0x22]), .IDEF, .PUSHB([8]), .ENDF, .CLEAR)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIDEF_redefineUnusedOpcode() {
    var instance = getInstance(maxp: .init(maxInstructionDefs: 1))

    instance.run(
      .notGlyf(),
      instructions: .PUSHB([0x90]),
      .IDEF,
      .PUSHB([8]),
      .ENDF,
      .PUSHB([0x90]),
      .IDEF,
      .PUSHB([42]),
      .ENDF,
      .literal(0x90)
    )
    instance.expectedEngineState.stack = [42]
    instance.validate()
  }

  @Test func testIDEF_outOfRangeInsideMargin() {
    var instance = getInstance(maxp: .init(maxInstructionDefs: 0))

    let instructions: [HintingInstruction] = [
      .PUSHB([0x96, 0x95, 0x94, 0x93]),
      .IDEF, .PUSHB([42]), .ENDF,
      .IDEF, .PUSHB([43]), .ENDF,
      .IDEF, .PUSHB([44]), .ENDF,
      .IDEF, .PUSHB([45]), .ENDF,
      .literal(0x93),
      .literal(0x94),
      .literal(0x95),
      .literal(0x96),
    ]

    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = [45, 44, 43, 42]
    instance.validate()
  }

  @Test func testIDEF_outOfRangeOutsideMargin() {
    var instance = getInstance(maxp: .init(maxInstructionDefs: 0))

    let instructions: [HintingInstruction] = [
      .PUSHB([0x97, 0x96, 0x95, 0x94, 0x93]),
      .IDEF, .ENDF,  // Empty definitions count against the limit!
      .IDEF, .ENDF,
      .IDEF, .ENDF,
      .IDEF, .ENDF,
      .IDEF, .ENDF,
    ]

    instance.run(.notGlyf(), instructions: instructions, failure: .maxpLimitExceeded)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIDEF_replaceDefinitionAtMargin() {
    var instance = getInstance(maxp: .init(maxInstructionDefs: 0))

    let instructions: [HintingInstruction] = [
      .PUSHB([0x93]), .IDEF, .PUSHB([42]), .ENDF,
      .PUSHB([0x94]), .IDEF, .PUSHB([43]), .ENDF,
      .PUSHB([0x95]), .IDEF, .PUSHB([44]), .ENDF,
      .PUSHB([0x96]), .IDEF, .PUSHB([45]), .ENDF,
      .literal(0x96),
      .PUSHB([0x96]), .IDEF, .PUSHB([46]), .ENDF,
      .literal(0x96),
      .PUSHB([0x97]), .IDEF, .PUSHB([47]), .ENDF,
    ]

    instance.run(.notGlyf(), instructions: instructions, failure: .maxpLimitExceeded)
    instance.expectedEngineState.stack = [46, 45]
    instance.validate()
  }

  @Test func testIDEF_cannotDefineInGlyf() {
    runNegativeTest(
      .glyf,
      instructions: .PUSHB([0x94]),
      .IDEF,
      .PUSHB([0xaa]),
      .ENDF,
      failure: .definitionsNotAllowedInGlyf
    )
  }

  @Test func testIDEF_persistsBetweenPrograms() throws {
    var instance = getInstance(maxp: .init(maxInstructionDefs: 2))
    instance.run(.fpgm, instructions: .PUSHB([0x93]), .IDEF, .PUSHB([45]), .ENDF)

    instance.expectedEngineState = nil
    instance.run(.prep, instructions: .PUSHB([0x94]), .IDEF, .PUSHB([32]), .ENDF, .literal(0x93))
    instance.expectedEngineState.stack = [45]
    instance.validate()

    instance.run(.glyf, instructions: .literal(0x93), .literal(0x94))

    instance.expectedEngineState.stack = [32, 45]
    instance.validate()
  }

  @Test func testIDEF_emptyDefinition() {
    var instance = getInstance(maxp: .init(maxInstructionDefs: 1))

    instance.run(.notGlyf(), instructions: .PUSHB([0x8, 0x90]), .IDEF, .ENDF, .literal(0x90))
    instance.expectedEngineState.stack = [0x8]
    instance.validate()
  }

  @Test func testUnIDEF() {
    runNegativeTest(instructions: .literal(0x28), failure: .illegalInstruction)
  }

  @Test func testIDEF_nestedFDEF() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 1, maxInstructionDefs: 1))

    let instructions: [HintingInstruction] = [
      .PUSHB([0x93]),
      .IDEF,
      .PUSHB([0]),
      .FDEF,
      .POP,
      .ENDF,
      .ENDF,
    ]

    instance.run(.notGlyf(), instructions: instructions, failure: .definitionsCannotBeNested)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIDEF_nestedIDEF() {
    var instance = getInstance(maxp: .init(maxInstructionDefs: 2))

    let instructions: [HintingInstruction] = [
      .PUSHB([0x93]),
      .IDEF,
      .PUSHB([0x94]),
      .IDEF,
      .POP,
      .ENDF,
      .ENDF,
    ]

    instance.run(.notGlyf(), instructions: instructions, failure: .definitionsCannotBeNested)
    instance.expectedEngineState.stack = []
    instance.validate()
  }

  @Test func testIDEF_tooFewStackElements() {
    runStackUnderflowTests(opcode: .IDEF, parameters: 1)
  }

  @Test func testIDEF_pushingSuspiciousBytes() {
    var instance = getInstance(maxp: .init(maxFunctionDefs: 1))
    let stackBytes: [UInt8] = [
      HintingInstruction.ENDF.opcode, HintingInstruction.IDEF.opcode, HintingInstruction.FDEF.opcode,
    ]
    let instructions: [HintingInstruction] = [
      .PUSHB([0xa0]), .IDEF, .PUSHB(stackBytes), .ENDF,
      .literal(0xa0),
    ]
    instance.run(.notGlyf(), instructions: instructions)

    instance.expectedEngineState.stack = stackBytes.reversed().map(Int32.init)
    instance.validate()
  }

  // MARK: - ROLL 0x8A
  /*
   Performs a circular shift of the top three stack elements.
   Pops the top three stack elements, a, b, and c and performs a circular shift of these top
   three objects on the stack with the effect being to move the third element to the top of the
   stack and to move the first two elements down one position. ROLL is equivalent to MINDEX[]
   with the value 3 at the top of the stack.
   */

  @Test func testROLL() {
    var instance = getInstance()
    instance.run(instructions: .NPUSHB([7, 4, 2]), .ROLL)
    instance.expectedEngineState.stack = [7, 2, 4]
    instance.validate()
  }

  @Test func testROLL_tooFewStackElements() {
    runNegativeTest(instructions: .ROLL, failure: .stackUnderflow)
    runNegativeTest(instructions: .PUSHB([7]), .ROLL, expectingProperties: [.stack([7])], failure: .stackUnderflow)
  }

  @Test func testROLL_tooFewStackElements2() {
    runNegativeTest(instructions: .NPUSHB([7, 4]), .ROLL, failure: .stackUnderflow)
  }

  // MARK: - MAX 0x8B
  /*
   Returns the larger of the top two stack elements.
   Pops two elements, e2 and e1, from the stack and pushes the larger of these two quantities onto the stack.
   */
  @Test func testMAX() {
    func testMAXCase(_ a: Int32, _ b: Int32, result: Int32) {
      var instance = getInstance()
      instance.run(instructions: .pushInt32(a), .pushInt32(b), .MAX)

      instance.expectedEngineState.stack = [result]
      instance.validate()
    }

    testMAXCase(0, 0, result: 0)
    testMAXCase(0, 1, result: 1)
    testMAXCase(1, 0, result: 1)
    testMAXCase(2, 1, result: 2)
    testMAXCase(1, 2, result: 2)
    testMAXCase(2, 2, result: 2)
    testMAXCase(-1, 1, result: 1)
    testMAXCase(1, -1, result: 1)
    testMAXCase(-1, -1, result: -1)
    testMAXCase(-2, -1, result: -1)
    testMAXCase(-1, -2, result: -1)
    testMAXCase(.max, 0, result: .max)
    testMAXCase(.max, .min, result: .max)
    testMAXCase(0, .min, result: 0)
  }

  @Test func testMAX_tooFewStackElements() {
    runStackUnderflowTests(opcode: .MAX, parameters: 2)
  }

  // MARK: - MIN 0x8C
  /*
   Returns the minimum of the top two stack elements.
   Pops two elements, e2 and e1, from the stack and pushes the smaller of these two quantities onto the stack.
   */
  @Test func testMIN() {
    func testMINCase(_ a: Int32, _ b: Int32, result: Int32) {
      var instance = getInstance()
      instance.run(instructions: .pushInt32(a), .pushInt32(b), .MIN)

      instance.expectedEngineState.stack = [result]
      instance.validate()
    }

    testMINCase(0, 0, result: 0)
    testMINCase(0, 1, result: 0)
    testMINCase(1, 0, result: 0)
    testMINCase(2, 1, result: 1)
    testMINCase(1, 2, result: 1)
    testMINCase(2, 2, result: 2)
    testMINCase(-1, 1, result: -1)
    testMINCase(1, -1, result: -1)
    testMINCase(-1, -1, result: -1)
    testMINCase(-2, -1, result: -2)
    testMINCase(-1, -2, result: -2)
    testMINCase(.max, 0, result: 0)
    testMINCase(.max, .min, result: .min)
    testMINCase(0, .min, result: .min)
  }

  @Test func testMIN_tooFewStackElements() {
    runStackUnderflowTests(opcode: .MIN, parameters: 2)
  }

  // MARK: - SCANTYPE 0x8D
  @Test func testSCANTYPE_noValue() {
    runStackUnderflowTests(opcode: .SCANTYPE, parameters: 1)
  }

  @Test func testSCANTYPE0() {
    var instance = getInstance()
    instance.run(instructions: [
      .pushInt32(0x7aaa_1234), .SCANCTRL,
      .pushInt32(0), .SCANTYPE,
    ])
    instance.expectedEngineState.variables.scanControl = .init(rawValue: 0x0000_1234)
    instance.validate()
  }

  @Test func testSCANTYPE1() {
    var instance = getInstance()
    instance.run(instructions: [
      .pushInt32(0x7aaa_1234), .SCANCTRL,
      .pushInt32(1), .SCANTYPE,
    ])
    instance.expectedEngineState.variables.scanControl = .init(rawValue: 0x0001_1234)
    instance.validate()
  }

  @Test func testSCANTYPE2() {
    var instance = getInstance()
    instance.run(instructions: [
      .pushInt32(0x7aaa_1234), .SCANCTRL,
      .pushInt32(2), .SCANTYPE,
    ])
    instance.expectedEngineState.variables.scanControl = .init(rawValue: 0x0002_1234)
    instance.validate()
  }

  @Test func testSCANTYPE3() {
    // when SCANTYPE is given a value outside its expected range it leaves the existing value untouched.
    let expected: UInt32 = 0x7aaa_1234

    var instance = getInstance()
    instance.run(instructions: [
      .pushInt32(0x7aaa_1234), .SCANCTRL,
      .pushInt32(3), .SCANTYPE,
    ])
    instance.expectedEngineState.variables.scanControl = .init(rawValue: expected)
    instance.validate()
  }

  // MARK: - INSTCTRL 0x8E
  @Test func testINSTCTRL_noValue() {
    runStackUnderflowTests(opcode: .INSTCTRL, parameters: 1)
  }

  @Test func testINSTCTRL_oneValue() {
    runNegativeTest(instructions: [.pushInt32(0), .INSTCTRL], failure: .stackUnderflow)
  }

  @Test func testINSTCTRL_fpgm() {
    var instance = getInstance()
    instance.run(
      .fpgm,
      instructions: [
        .pushInt32(1),
        .pushInt32(1),
        .INSTCTRL,
      ]
    )
    instance.validate()
  }

  @Test func testINSTCTRL_glyf() {
    var instance = getInstance()
    instance.run(
      .glyf,
      instructions: [
        .pushInt32(1),
        .pushInt32(1),
        .INSTCTRL,
      ]
    )
    instance.validate()
  }

  @Test func testINSTCTRL_1() {
    var instance = getInstance()
    instance.run(
      .prep,
      instructions: [
        .pushInt32(1),
        .pushInt32(1),
        .INSTCTRL,
      ]
    )
    instance.expectedEngineState.variables.instructControl = .noGridFit
    instance.validate()
  }

  @Test func testINSTCTRL_1_wrong() {
    var instance = getInstance()
    instance.run(
      .prep,
      instructions: [
        .pushInt32(2),
        .pushInt32(1),
        .INSTCTRL,
      ]
    )
    instance.expectedEngineState.variables.instructControl = []
    instance.validate()
  }

  @Test func testINSTCTRL_2() {
    var instance = getInstance()
    instance.run(
      .prep,
      instructions: [
        .pushInt32(2),
        .pushInt32(2),
        .INSTCTRL,
      ]
    )
    instance.expectedEngineState.variables.instructControl = .default
    instance.validate()
  }

  @Test func testINSTCTRL_2_wrong() {
    var instance = getInstance()
    instance.run(
      .prep,
      instructions: [
        .pushInt32(1),
        .pushInt32(2),
        .INSTCTRL,
      ]
    )
    instance.expectedEngineState.variables.instructControl = []
    instance.validate()
  }

  @Test func testINSTCTRL_unknownSelector() {
    for i in Int32(-16)..<Int32(16) {
      if [1, 2].contains(i) {
        continue
      }
      var instance = getInstance()
      instance.run(
        .prep,
        instructions: [
          .pushInt32(i),
          .pushInt32(i),
          .INSTCTRL,
        ]
      )
      instance.validate()
    }
  }

  // MARK: - PUSHB 0xB0-0xB7
  /*
   Takes the specified number of bytes from the instruction stream and pushes them onto the
   interpreter stack.
   The variables a, b, and c are binary digits representing numbers from 000 to 111 (0-7 in
   binary). The value 1 is automatically added to the abc figure to obtain the actual number of
   bytes pushed.
   When byte values are pushed onto the stack they are non-sign extended with zeroes to form 32
   bit numbers.
   */

  @Test func testPUSHB_oneByte() {
    let byte: UInt8 = 0x83

    var instance = getInstance()
    instance.run(instructions: .PUSHB([byte]))

    instance.expectedEngineState.stack.append(Int32(byte))
    instance.validate()
  }

  @Test func testPUSHB_8Bytes() {
    var bytes = [UInt8]()
    for idx: UInt8 in 0..<8 { bytes.append(idx) }
    var instance = getInstance()
    instance.run(instructions: .PUSHB(bytes))

    for idx in 0..<8 {
      instance.expectedEngineState.stack.append(Int32(7 - idx))
    }
    instance.validate()
  }

  @Test func testPUSHB_insufficientBytes() {
    for numBytes in 1...8 {
      runNegativeTest(
        instructions: .PUSHB(Array(repeating: 0xaa, count: numBytes - 1), n: UInt8(numBytes)),
        expectingProperties: [.stack([])],
        failure: .ranOffEndOfInstructions
      )
    }
  }

  // MARK: - PUSHW 0xB8-0xBF
  /*
   Takes the specified number of words from the instruction stream and pushes them onto the
   interpreter stack.
   The variables a, b, and c are binary digits representing numbers from 000 to 111 (0-7
   binary). The value 1 is automatically added to the abc figure to obtain the actual number of
   bytes pushed.
   When word values are pushed onto the stack they are sign extended to 32 bits.
   The most significant byte of each word comes first in the instruction stream.
   */

  @Test func testPUSHW_oneWord() {
    let word: Int16 = 0x34ab
    var instance = getInstance()
    instance.run(instructions: .PUSHW([word]))

    instance.expectedEngineState.stack.append(0x34ab)
    instance.validate()
  }

  @Test func testPUSHW_8Words() {
    var words = [Int16]()
    for idx: Int16 in 0..<8 { words.append((0x74 << 8) + idx) }
    var instance = getInstance()
    instance.run(instructions: .PUSHW(words))

    for idx in 0..<8 {
      instance.expectedEngineState.stack.append(Int32((0x74 << 8) + 7 - idx))
    }
    instance.validate()
  }

  @Test func testPUSHW_signExtendNegative() {
    let word: Int16 = -801
    var instance = getInstance()
    instance.run(instructions: .PUSHW([word]))

    instance.expectedEngineState.stack.append(Int32(word))
    instance.validate()
  }

  @Test func testPUSHW_insufficientWords() {
    for numBytes in 1...8 {
      runNegativeTest(
        instructions: .PUSHW(Array(repeating: 0x4aaa, count: numBytes - 1), n: UInt8(numBytes)),
        failure: .ranOffEndOfInstructions
      )
    }
  }

  @Test func testPUSHW_zeroMaxStackElements() {
    let word: Int16 = 0x34ab
    var instance = getInstance(maxp: .init(maxStackElements: 0))
    instance.run(.glyf, instructions: .PUSHW([word]))

    instance.expectedEngineState.stack.append(Int32(word))
    instance.validate()
  }
  // MARK: GETVARIATION 0x91
  @Test func testGETVARIATION_empty() {
    // with no variations, this should raise an error.
    runNegativeTest(instructions: .GETVARIATION, failure: .illegalInstruction)
  }

  @Test func testGETVARIATION_empty_definedIDEF() {
    var instance = getInstance()
    instance.run(.notGlyf(), instructions: .PUSHB([0x91]), .IDEF, .PUSHB([0xdd]), .ENDF, .GETVARIATION)

    instance.expectedEngineState.stack = [0xdd]
    instance.validate()
  }

  @Test func testGETVARIATION_nonEmpty() {
    let coord: [F2Dot14] = [0.5, 1, -0.5, -1]
    var instance = getInstance()
    instance.setVariationCoord(coord)
    instance.run(instructions: .GETVARIATION)

    instance.expectedEngineState.stack = coord.reversed().map { Int32($0.bitPattern) }
    instance.validate()
  }

  @Test func testGETVARIATION_null_0lenght() {
    var instance = getInstance()
    instance.setNullVariationCoord(count: 0)
    // GETVARIATION should fail because this would mean the font is not variable.
    instance.run(instructions: .GETVARIATION, failure: .illegalInstruction)
    instance.validate()
  }

  @Test func testGETVARIATION_null_5lenght() {
    var instance = getInstance()
    instance.setNullVariationCoord(count: 5)
    instance.run(instructions: .GETVARIATION)

    instance.expectedEngineState.stack = Array(repeating: 0, count: 5)
    instance.validate()
  }

  // MARK: - GETDATA 0x92
  @Test func testGETDATA_emptyStack() {
    runNegativeTest(instructions: .GETDATA, failure: .stackUnderflow)
  }

  @Test func testGETDATA_badSelectors() {
    for i in 0..<16 {
      if i == 1 { continue }
      var instance = getInstance(maxp: .init(maxPoints: 16))
      instance.run(instructions: [.pushInt32(0), .GETDATA])
      instance.expectedEngineState.stack = [0]
      instance.validate()
    }
  }

  @Test func testGETDATA_randomlmao_zero() {
    runNegativeTest(instructions: [.pushInt32(0), .pushInt32(1), .GETDATA], failure: .invalidOperand)
  }

  @Test func testGETDATA_randomlmao_5() {
    var instance = getInstance(maxp: .init(maxPoints: 16))
    instance.run(instructions: [.pushInt32(5), .pushInt32(1), .GETDATA])
    instance.expectedEngineState.stack = [1, 2]
    instance.validate()
  }

  @Test func testGETDATA_randomlmao_21() {
    var instance = getInstance(maxp: .init(maxPoints: 16))
    instance.run(instructions: [.pushInt32(21), .pushInt32(1), .GETDATA])
    instance.expectedEngineState.stack = [1, 17]
    instance.validate()
  }

  // MARK: - MDRP 0xC0-0xDF
  @Test func testMDRP_stackunderflow() {
    runStackUnderflowTests(
      .glyf,
      opcode: .MDRP(distanceType: 0, roundDistance: false, useMinimumDistance: false, resetRP0: false),
      parameters: 1
    )
  }

  @Test func testMDRP_notGlyf() {
    runNegativeTest(
      .notGlyf(),
      instructions: .PUSHB([0]),
      .MDRP(distanceType: 0, roundDistance: false, useMinimumDistance: false, resetRP0: false),
      failure: .invalidAccessToGlyphZone
    )
  }

  @Test func testMDRP_fpgm() {
    runNegativeTest(
      .fpgm,
      instructions: .PUSHB([0, 0, 0]),
      .SZPS,
      .SRP0,
      .MDRP(distanceType: 0, roundDistance: false, useMinimumDistance: false, resetRP0: false),
      exemptingProperties: .zonePointers,
      failure: .invalidAccessToTwilightZone
    )
  }

  @Test func testMDRP_missingRP0() {
    runNegativeTest(
      .glyf,
      instructions: [
        .PUSHB([0, 44]), .SRP0,
        .MDRP(distanceType: 0, roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ],
      expectingProperties: [.variable(\.rp0, 44)],
      failure: .noSuchPoint
    )
  }

  @Test func testMDRP_missingStackPoint() {
    runNegativeTest(
      .glyf,
      instructions: [
        .SVTCA_X,  // Make sure the interpreter sets OldProj first
        .pushInt32(12),
        .MDRP(distanceType: 0, roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ],
      failure: .noSuchPoint
    )
  }

  @Test func testMDRP_twilight_noCutIn_noMinDistance_noRound_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 2.25),
        .init(x: 2.00, y: 3.00),
        .init(x: 3.75, y: 4.75),
      ],
      scaled: [
        .init(x: 12.5, y: 13.5),
        .init(x: 20.0, y: 21.0),
        .init(x: 37.5, y: 38.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 19.5, y: 4.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_unscaled_noCutIn_noMinDistance_noRound_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 2.25),
        .init(x: 2.00, y: 3.00),
        .init(x: 3.75, y: 4.75),
      ],
      scaled: [
        .init(x: 12.5, y: 13.5),
        .init(x: 20.0, y: 21.0),
        .init(x: 37.5, y: 38.5),
      ],
      original: [
        .init(x: 125, y: 126),
        .init(x: 200, y: 201),
        .init(x: 375, y: 376),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .SRP0,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.glyphPoints[point: 2].moveTo(x: 45.75, y: 4.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_unscaled_nonSquareEm() {
    // Exercises MDRP's `unitsPerEmScale.x != .y` branch (the non-square em
    // path). Default xStretch/yStretch are equal; passing different values
    // makes the per-axis em scales unequal so the unscaled-distance scaling
    // goes through the per-axis path instead of the single-scale fast path.
    //
    // pt1.original.x - pt0.original.x = 8 was chosen so that the per-axis
    // `mixedMulRoundingToNearestOrUp(unitsPerEmScale.x)` lands exactly on
    // the round-half-toward-positive tie-break in Math.mixedMul:
    // product = 8 * unitsPerEmScale.x.bitPattern (= 4096) = 32768, which is
    // exactly `half` for an F16Dot16 multiplier (divisor = 65536).
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setScaleFactors(xStretch: 2, yStretch: 1)
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 2.25),
        .init(x: 2.00, y: 3.00),
        .init(x: 3.75, y: 4.75),
      ],
      scaled: [
        .init(x: 12.5, y: 13.5),
        .init(x: 20.0, y: 21.0),
        .init(x: 37.5, y: 38.5),
      ],
      original: [
        .init(x: 125, y: 126),
        .init(x: 133, y: 126),
        .init(x: 375, y: 376),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .SRP0,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ]
    )
    // Don't validate points/refs — the exact moved-to coordinates depend on
    // the per-axis scaling math; we just need this path executed.
    instance.validate(except: [.glyphPoints, .referencePoints, .zonePointers])
  }

  @Test func testMDRP_unscaledOutlineIsWrong() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 2.25),
        .init(x: 2.00, y: 3.00),
        .init(x: 3.75, y: 4.75),
      ],
      scaled: [
        .init(x: 12.5, y: 13.5),
        .init(x: 20.0, y: 21.0),
        .init(x: 37.5, y: 38.5),
      ],
      original: [
        .init(x: 125, y: 126),
        .init(x: 200, y: 201),
        .init(x: 375, y: 376),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(1), .SZPS,
        .pushInt32(1), .SRP0,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ],
      unscaledOutlineIsWrong: true
    )
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.glyphPoints[point: 0] = OutlinePoint(
      original: .init(x: 5, y: 9),
      scaled: .init(x: 12.5, y: 13.5),
      hinted: .init(x: 1.25, y: 2.25)
    )
    instance.expectedEngineState.glyphPoints[point: 1] = OutlinePoint(
      original: .init(x: 8, y: 12),
      scaled: .init(x: 20.0, y: 21.0),
      hinted: .init(x: 2.0, y: 3.0)
    )
    instance.expectedEngineState.glyphPoints[point: 2] = OutlinePoint(
      original: .init(x: 15, y: 19),
      scaled: .init(x: 37.5, y: 38.5),
      hinted: .init(x: 3.75, y: 4.75),
      xMoved: true
    )
    instance.validate()
  }

  @Test func testMDRP_twilight_noCutIn_noMinDistance_noRound_resetRP0() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: true),
      ]
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 2
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 19.5, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_twilight_noCutIn_minDistanceNegative_noRound_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .setPV(.init(x: -1, y: 0)),
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,
        .pushF26Dot6(30), .SMD,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: true, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.projectionVector = .init(x: -1, y: 0)
    instance.expectedEngineState.variables.minimumDistance = 30
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 32.0, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_twilight_noCutIn_minDistanceIntMin_noRound_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .setPV(.init(x: -1, y: 0)),
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,
        .pushF26Dot6(.min), .SMD,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: true, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.projectionVector = .init(x: -1, y: 0)
    instance.expectedEngineState.variables.minimumDistance = .min
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 19.5, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_twilight_noCutIn_minDistanceIntMax_noRound_noReset_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))

    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .setPV(.init(x: -1, y: 0)),
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,
        .pushF26Dot6(.max), .SMD,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: true, resetRP0: false),
      ],
      failure: .arithmeticError
    )

    instance.expectedEngineState.variables.projectionVector = .init(x: -1, y: 0)
    instance.expectedEngineState.variables.minimumDistance = .max
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.validate(except: .points)
  }

  @Test func testMDRP_twilight_noCutIn_minDistancePositive_noRound_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,
        .pushF26Dot6(30), .SMD,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: true, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.minimumDistance = 30
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 32.0, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_twilight_noCutIn_minDistanceNotRounded_rounding_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,
        .pushF26Dot6(30.5), .SMD,

          .pushInt32(2),
        .MDRP(roundDistance: true, useMinimumDistance: true, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.minimumDistance = 30.5
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 32.5, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_twilight_cutInNoChange_noMinDistance_noRound_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .setSingleWidthValue(2),
        .pushF26Dot6(2), .SSWCI,
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.singleWidthCutIn = 2
    instance.expectedEngineState.variables.singleWidthValue = 32
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 19.5, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_twilight_cutIn_noMinDistance_noRound_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .setSingleWidthValue(20.5),
        .pushF26Dot6(20.5), .SSWCI,
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,

          .pushInt32(2),
        .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.singleWidthCutIn = 20.5
    instance.expectedEngineState.variables.singleWidthValue = 328
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 19.5, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_twilight_cutIn_noMinDistance_round_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3))
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 1.25),
        .init(x: 2.00, y: 2.00),
        .init(x: 3.75, y: 3.75),
      ],
      scaled: [
        .init(x: 12.5, y: 12.5),
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .twilight
    )
    instance.run(
      .glyf,
      instructions: [
        .setSingleWidthValue(20.5),
        .pushF26Dot6(20.5), .SSWCI,
        .SVTCA_X,
        .pushInt32(0), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .SRP0,

          .pushInt32(2),
        .MDRP(roundDistance: true, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.singleWidthCutIn = 20.5
    instance.expectedEngineState.variables.singleWidthValue = 328
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 1
    instance.expectedEngineState.variables.rp2 = 2
    instance.expectedEngineState.twilightPoints[point: 2].moveTo(x: 20.0, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMDRP_pedanticZoneChecks1() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [.PUSHB([0]), .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: false)],
      failure: .maxpLimitExceeded
    )
    instance.validate()
  }

  @Test func testMDRP_pedanticZoneChecks2() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 16))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0]), .SZP0,
        .PUSHB([0]), .MDRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ],
      failure: .maxpLimitExceeded
    )
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.validate()
  }

  // MARK: - MIRP 0xE0-0xFF
  @Test func testMIRP_stackunderflow_0() {
    runNegativeTest(
      instructions: .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      failure: .stackUnderflow
    )
  }

  @Test func testMIRP_stackunderflow_1() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 16))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    runNegativeTest(
      fUnitControlValues: [0],
      instructions:
          .pushInt32(0),
      .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      failure: .stackUnderflow
    )
  }

  // cpp doesnt care about cvt in fpgm, it'll always read zero. still fails, but after consuming both operands.
  // stti croaks after the oob cvt read attempt before popping the second operand.
  @Test func testMIRP_missingCvt_fpgm() {
    runNegativeTest(
      .fpgm,
      instructions:
          .pushInt32(0),
      .pushInt32(4_000),
      .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      failure: .cvtLocationOutOfBounds
    )
  }

  @Test func testMIRP_missingCvt_notFpgm() {
    runNegativeTest(
      .glyf,
      instructions:
          .pushInt32(0),
      .pushInt32(4_000),
      .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      expectingProperties: [.stack([0])],
      failure: .cvtLocationOutOfBounds
    )
  }

  @Test func testMIRP_pointOOB() {
    runNegativeTest(
      .glyf,
      fUnitControlValues: [0],
      instructions:
          .pushInt32(4_000),
      .pushInt32(0),
      .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      failure: .noSuchPoint
    )
  }

  @Test func testMIRP_semiOOB() {
    var instance = getInstance(maxp: .init(maxPoints: .max), cvtCount: 256)
    instance.setPoints([.zero], forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([255, 255]), .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.glyphPoints[point: 255].xMoved = true
    instance.expectedEngineState.variables.rp2 = 255
    instance.validate()
  }

  @Test func testMIRP_glyph_noAutoFlip_noRounding_noMinDistance_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([2.5])
    instance.setPoints(
      [
        OutlinePoint(x: 1.25, y: 2.25),
        OutlinePoint(x: 2.75, y: 3.75),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(10), .SRP1,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .pushInt32(0),
        .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 3.75, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMIRP_glyph_noAutoFlip_noRounding_noMinDistance_reset() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([2.5])
    instance.setPoints(
      [
        OutlinePoint(x: 1.25, y: 2.25),
        OutlinePoint(x: 2.75, y: 3.75),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushInt32(10), .SRP1,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .pushInt32(0),
        .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: true),
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 3.75, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMIRP_glyph_autoFlip_noRounding_noMinDistance_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([2.5])
    instance.setPoints(
      [
        OutlinePoint(x: 2.75, y: 3.75),
        OutlinePoint(x: 1.25, y: 2.25),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .FLIPON,
        .SVTCA_X,
        .pushInt32(10), .SRP1,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .pushInt32(0),
        .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.autoFlip = true
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 0.25, y: 2.25, xMoved: true)
    instance.validate()
  }

  @Test func testMIRP_glyph_noAutoFlip_roundNoCutIn_noMinDistance_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([2.5])
    instance.setPoints(
      [
        OutlinePoint(x: 1.25, y: 2.25),
        OutlinePoint(x: 2.75, y: 3.75),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .FLIPOFF,
        .SVTCA_X,
        .pushInt32(10), .SRP1,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .pushInt32(0),
        .MIRP(roundDistance: true, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.autoFlip = false
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 4.25, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMIRP_glyph_noAutoFlip_roundCutInNegative_noMinDistance_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([2.5])
    instance.setPoints(
      hinted: [
        .init(x: 1.25, y: 2.25),
        .init(x: 2.75, y: 3.75),
      ],
      scaled: [
        .init(x: -10, y: -10),
        .init(x: -10, y: -10),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .FLIPOFF,
        .SVTCA_X,
        .pushInt32(10), .SRP1,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .pushInt32(0),
        .MIRP(roundDistance: true, useMinimumDistance: false, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.autoFlip = false
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.25, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMIRP_glyph_noAutoFlip_noRounding_minDistance_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([2.5])
    instance.setPoints(
      [
        OutlinePoint(x: 1.25, y: 2.25),
        OutlinePoint(x: 2.75, y: 3.75),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushF26Dot6(30), .SMD,
        .pushInt32(10), .SRP1,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .pushInt32(0),
        .MIRP(roundDistance: false, useMinimumDistance: true, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.minimumDistance = 30
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 31.25, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMIRP_twilight_noAutoFlip_noRounding_minDistance_noReset() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([2.5])
    instance.setPoints(
      [
        OutlinePoint(scaled: FixedCoord(x: 1, y: 2), hinted: FixedCoord(x: 1.25, y: 2.25)),
        OutlinePoint(scaled: FixedCoord(x: 2, y: 3), hinted: FixedCoord(x: 2.75, y: 3.75)),
      ],
      forZone: .twilight
    )
    instance.setPoints(
      [
        OutlinePoint(scaled: FixedCoord(x: 3, y: 4), hinted: FixedCoord(x: 3.5, y: 5.5)),
        OutlinePoint(scaled: FixedCoord(x: 5, y: 6), hinted: FixedCoord(x: 10.5, y: 13.5)),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .SVTCA_X,
        .pushF26Dot6(30), .SMD,
        .pushInt32(10), .SRP1,
        .pushInt32(1), .SZP0,
        .pushInt32(0), .SZP1,
        .pushInt32(1), .pushInt32(0),
        .MIRP(roundDistance: false, useMinimumDistance: true, resetRP0: false),
      ]
    )
    instance.expectedEngineState.variables.minimumDistance = 30
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.twilightPoints[point: 1].scaled = FixedCoord(x: 5.5, y: 4)
    instance.expectedEngineState.twilightPoints[point: 1].moveTo(x: 33.5, y: 5.5, xMoved: true)
    instance.validate()
  }

  @Test func testMIRP_twilight_noCutIn_minDistanceIntMax_noRound_noReset_movePointOverflow() {
    var instance = getInstance(maxp: .init(maxPoints: 3, maxTwilightPoints: 3), cvtCount: 1)
    instance.setCVT([.max])

    instance.setPoints(
      hinted: [
        .init(x: 2.00, y: 2.00),
        .init(x: 10_000, y: .min),
      ],
      scaled: [
        .init(x: 20.0, y: 20.0),
        .init(x: 37.5, y: 37.5),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .setPV(.init(x: -1, y: 0)),
        .pushInt32(0), .SRP0,
        .pushF26Dot6(.max), .SMD,

          .PUSHB([1, 0]),
        .MIRP(roundDistance: false, useMinimumDistance: true, resetRP0: false),
      ],
      failure: .arithmeticError
    )

    instance.expectedEngineState.variables.projectionVector = .init(x: -1, y: 0)
    instance.expectedEngineState.variables.minimumDistance = .max
    instance.validate(except: .points)
  }

  @Test func testMIRP_rotatedProjectionVector() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([2.5])
    instance.setPoints(
      [
        OutlinePoint(x: 1.25, y: 2.25),
        OutlinePoint(x: 2.75, y: 3.75),
      ],
      forZone: .glyph
    )
    instance.run(
      .glyf,
      instructions: [
        .PUSHB([0, 1]), .SPVTL_1,
        .pushInt32(10), .SRP1,
        .pushInt32(1), .SZP0,
        .pushInt32(1), .SZP1,
        .pushInt32(1), .pushInt32(0),
        .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: true),
        .SPVTCA_X,
      ]
    )
    instance.expectedEngineState.variables.zp0 = .glyph
    instance.expectedEngineState.variables.zp1 = .glyph
    instance.expectedEngineState.variables.rp0 = 1
    instance.expectedEngineState.variables.rp1 = 0
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 6.28125, y: 3.75, xMoved: true)
    instance.validate()
  }

  @Test func testMIRP_noAutoflip_rounding_minDistance_correctlyClampDistanceToMoveDirection() {
    var instance = getInstance(maxp: .init(maxPoints: 2, maxTwilightPoints: 2), cvtCount: 1)
    instance.setCVT([.init(bitPattern: -30)])
    instance.setPoints(
      [
        .zero,  // reference point
        OutlinePoint(x: 0.75, y: 4.734375),  // to-be-moved point
      ],
      forZone: .glyph
    )

    instance.run(
      .glyf,
      instructions: [
        .PUSHB([1, 0, 255]),
        .SCVTCI,
        .FLIPOFF,
        .MIRP(roundDistance: true, useMinimumDistance: true, resetRP0: false),
      ]
    )

    instance.expectedEngineState.glyphPoints[point: 1].moveTo(x: 1.0, y: 4.734375, xMoved: true)
    instance.expectedEngineState.variables.rp2 = 1
    instance.expectedEngineState.variables.autoFlip = false
    instance.expectedEngineState.variables.controlValueCutIn = .init(bitPattern: 255)
    instance.validate()
  }

  @Test func testMIRP_pedanticZoneChecks() {
    var instance = getInstance(maxp: .init(maxPoints: 2))
    instance.setPoints(Array(repeating: .zero, count: 16), forZone: .glyph)
    instance.run(
      .glyf,
      instructions: [.PUSHB([0, 0]), .MIRP(roundDistance: false, useMinimumDistance: false, resetRP0: false)],
      failure: .maxpLimitExceeded
    )
    instance.validate()
  }
}

@Suite struct RoundStateTests {
  @Test func testSRoundInterestingValues() {
    let sround = RoundState(superRoundParameter: 50)
    #expect(sround.period == 0.5)
    #expect(sround.phase == 0.375)
    #expect(sround.threshold == -0.125)
  }

  @Test func testS45RoundInterestingValues0() {
    let s45round = RoundState(super45RoundParameter: 0)
    #expect(s45round.period == 0x1.6a09e668p-2)
    #expect(s45round.phase == 0)
    #expect(s45round.threshold == 0.34375)
  }

  @Test func testSRoundRoundtrip() {
    for i in 0..<256 {
      let sround = RoundState(superRoundParameter: UInt8(i))
      #expect(sround.superParameter == UInt8(i))
    }
  }

  @Test func testS45RoundRoundtrip() {
    // it is not possible to revert values reliably above 192 because
    // period45.bitPattern being 999 results in a period value of 0
    for i in 0..<192 {
      let s45round = RoundState(super45RoundParameter: UInt8(i))
      #expect(s45round.super45Parameter == UInt8(i))
    }
  }
}

private struct F27Dot5: FixedPoint {
  var bitPattern: Int32
  @_transparent static var fractionBits: Int { 5 }

  @_transparent init(bitPattern: Int32) {
    self.bitPattern = bitPattern
  }

  @_transparent static var defaultRounding: RoundingRule { .toNearestOrAway }
}
