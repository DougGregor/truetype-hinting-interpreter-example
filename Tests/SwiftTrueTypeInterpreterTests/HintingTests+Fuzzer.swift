// Fuzzer-discovered interpreter bugs translated into stable regression tests.

import SwiftTrueTypeInterpreter
import Testing

extension HintingTests {
  // Fatal recursion depth in IUPRangeIterator.next()
  @Test func testFuzzerRecursionBombIUP() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 21_364,
      maxPoints: 28_777,
      maxContours: 25_701,
      maxCompositePoints: 20_085,
      maxCompositeContours: 28_005,
      maxElements: 29_186,
      maxTwilightPoints: 514,
      maxStorage: 514,
      maxFunctionDefs: 514,
      maxInstructionDefs: 587,
      maxStackElements: 32_256,
      maxSizeOfInstructions: 0,
      maxComponentElements: 0,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 0)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 0),
      yStretch: .init(bitPattern: 1_024),
      unitsPerEm: 0,
      pointSize: -100_709_813,
      cvtScale: .init(bitPattern: 1_024),
      isRotated: true,
      isStretched: true
    )
    instance.run(
      .prep,
      instructions: [
        .MPPEM, .PUSHB([180, 180, 180, 180, 180, 75, 75]), .MPPEM, .MPPEM, .SZPS, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
        .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .CEILING, .MPPEM, .ABS,
        .SFVTL_0, .SVTCA_Y, .DIV, .WS, .MPS, .MPPEM, .MPPEM, .MPPEM, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
        .SVTCA_Y, .SVTCA_Y, .ABS, .NEG, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM,
        .MPPEM, .MPPEM, .MPPEM, .MPPEM, .SZPS, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .MPPEM, .SHC_0, .SHZ_0, .IP,
        .SHZ_0, .IUP_Y, .SHZ_0, .SHZ_0, .SHZ_0, .PUSHB([75, 75, 247]), .MDAP_0, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
        .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .GC_0, .SVTCA_Y, .ABS, .NEG, .SUB, .DIV, .NROUND_0, .NEG,
        .literal(0xeb), .MPPEM, .MPPEM, .CEILING, .MPPEM, .ABS, .NEG, .ADD, .DIV, .WS, .MPPEM, .MPPEM, .SHC_0,
        .SHPIX, .SHC_0, .SHPIX, .MPPEM, .MPPEM, .ABS, .NEG, .ALIGNPTS, .SVTCA_X, .SVTCA_Y, .SVTCA_X,
      ]
    )

    instance.validate(except: .all)
  }

  // Fatal rounding error in FixedPoint.rounding(rule:)
  // FIXME: swift 6.5-dev (snapshot 2026-05-27-a) crashes the SIL memory lifetime
  // verifier compiling this function (MemoryLifetimeVerifier.cpp:263).
  /*
  @Test func testFuzzerUnrepresentableRounding() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 32_481,
      maxPoints: 57_825,
      maxContours: 57_825,
      maxCompositePoints: 25_569,
      maxCompositeContours: 57_600,
      maxElements: 12_032,
      maxTwilightPoints: 65_535,
      maxStorage: 65_535,
      maxFunctionDefs: 65_535,
      maxInstructionDefs: 65_535,
      maxStackElements: 65_535,
      maxSizeOfInstructions: 65_280,
      maxComponentElements: 0,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: -251_592_449)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 2_147_483_392),
      yStretch: .init(bitPattern: -4_042_752),
      unitsPerEm: 0,
      pointSize: 1_265_565_771,
      cvtScale: .init(bitPattern: 2_147_483_392),
      isRotated: true,
      isStretched: false
    )
    // warning: conversion from 0xff to HintingInstruction.MIRP not implemented, emitting literal
    // warning: emitting literal for unrecognized opcode 0x28
    let prep: [HintingInstruction] = [
      .SVTCA_Y, .MPPEM, .MPPEM, .MPPEM, .NOT, .NOT, .NOT, .NOT, .literal(0x28), .literal(0xff), .literal(0xff),
      .OR, .SVTCA_X,
    ]
    instance.run(.prep, instructions: prep, failure: .illegalInstruction)

    instance.expectedEngineState.cvt = [-3_931_132.015625]
    instance.expectedEngineState.stack = [1, 65_474, 65_474]
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.validate()
  }
  */

  // Fatal arithmetic overflow in SwiftTrueTypeInterpreter.FixedCartesian.magnitude()
  // FIXME: same swift 6.5-dev SIL verifier crash as testFuzzerUnrepresentableRounding.
  /*
  @Test func testFuzzerMagnitudeOverflow() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 21_364,
      maxPoints: 28_777,
      maxContours: 25_701,
      maxCompositePoints: 24_930,
      maxCompositeContours: 27_749,
      maxElements: 60_251,
      maxTwilightPoints: 45_659,
      maxStorage: 19_275,
      maxFunctionDefs: 48_566,
      maxInstructionDefs: 19_275,
      maxStackElements: 19_208,
      maxSizeOfInstructions: 0,
      maxComponentElements: 0,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 0)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 0),
      yStretch: .init(bitPattern: 0),
      unitsPerEm: 8_704,
      pointSize: 4_934_400,
      cvtScale: .init(bitPattern: 1),
      isRotated: false,
      isStretched: false
    )
    // warning: conversion from 0xeb to HintingInstruction.MIRP not implemented, emitting literal
    // warning: conversion from 0xff to HintingInstruction.MIRP not implemented, emitting literal
    let prep: [HintingInstruction] = [
      .MPPEM, .MPPEM, .SVTCA_Y, .SVTCA_Y, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM,
      .MPPEM, .SZPS, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .MPPEM, .MPPEM, .MPPEM, .CEILING, .MPPEM, .literal(0xff),
      .literal(0xff), .literal(0xff), .literal(0xff), .literal(0xff), .MPS, .SPVTCA_Y, .SPVTCA_Y, .SPVTCA_Y,
      .SPVTCA_Y, .SPVTCA_Y, .SPVTCA_Y, .SPVTCA_Y, .SPVTCA_Y, .SPVTCA_Y, .SPVTCA_Y, .MPS, .PUSHB([177, 177]),
      .SPVFS, .SPVFS, .PUSHB([0, 112]), .ROUND_1, .ABS, .NEG, .SUB, .DIV, .NROUND_0, .NEG, .literal(0xeb), .OR,
    ]
    instance.run(.prep, instructions: prep)

    instance.expectedEngineState.stack = [0, 0]
    instance.expectedEngineState.twilightPoints[point: 0] = .init(
      scaled: .zero,
      hinted: .init(x: 0.0, y: 5.84375),
      yMoved: true
    )
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .init(x: 1.171875, y: 1.171875)
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }
  */

  // Fatal arithmetic overflow in MIAP
  // FIXME: same swift 6.5-dev SIL verifier crash.
  /*
  @Test func testFuzzerArithmeticOverflowMIAP() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 8_192,
      maxPoints: 9_472,
      maxContours: 136,
      maxCompositePoints: 45_489,
      maxCompositeContours: 45_489,
      maxElements: 45_489,
      maxTwilightPoints: 45_489,
      maxStorage: 45_489,
      maxFunctionDefs: 45_489,
      maxInstructionDefs: 45_489,
      maxStackElements: 45_489,
      maxSizeOfInstructions: 45_489,
      maxComponentElements: 45_489,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: -867_480_757)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: -1),
      yStretch: .init(bitPattern: -15_792),
      unitsPerEm: 19_275,
      pointSize: 1_259_080_716,
      cvtScale: .init(bitPattern: -1),
      isRotated: true,
      isStretched: false
    )
    // warning: conversion from 0xc2 to HintingInstruction.MDRP not implemented, emitting literal
    // warning: conversion from 0xff to HintingInstruction.MIRP not implemented, emitting literal
    let prep: [HintingInstruction] = [
      .GPV, .GPV, .GPV, .GPV, .SZP1, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .SZPS,
      .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .S45ROUND, .S45ROUND,
      .S45ROUND, .S45ROUND, .CEILING, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .literal(0xff), .literal(0xff),
      .literal(0xff), .literal(0xff), .literal(0xff), .literal(0xff), .literal(0xc2), .LT, .MPPEM, .MPPEM, .MPPEM,
      .GPV, .GPV, .GPV, .MPPEM, .MPPEM, .SVTCA_Y, .SVTCA_Y, .GETINFO, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
      .SVTCA_Y, .SFVTPV, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SFVTCA_Y,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .GETINFO, .GETINFO, .GETINFO, .GETINFO, .GETINFO, .GETINFO, .MIAP_1,
      .GETINFO, .LOOPCALL, .GETINFO, .GETINFO, .GETINFO, .RS, .NROUND_0, .NROUND_3, .DELTAC1, .NEG, .ABS, .GT,
      .SUB, .NROUND_2, .CEILING, .NEG, .GETINFO, .CALL, .GETINFO, .GETINFO, .GETINFO, .GETINFO, .GETINFO,
      .GETINFO, .GETINFO, .GETINFO, .GC_0, .NROUND_0, .NROUND_3, .DELTAP3, .GETINFO, .SUB, .JROF,
      .PUSHW([184, 255]), .NEG,
    ]
    instance.run(.prep, instructions: prep, failure: .arithmeticError)

    instance.expectedEngineState.cvt = [-13_554_386.828125]
    instance.expectedEngineState.stack = [
      16_384, 0, 16_384, 0, 16_384, 0, 0, 0, 0, 0, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0,
      16_384, 0, 16_384, 0, 16_384, 0, 16_384, 16_384, 0, 16_384, 0, 16_384, 0, 16_384,
    ]
    instance.expectedEngineState.twilightPoints[point: 0] = .init(
      scaled: .init(x: 0.0, y: -33_554_432.0),
      yMoved: true
    )
    instance.expectedEngineState.twilightPoints[point: 16_384] = .init(
      scaled: .zero,
      hinted: .init(x: 0.0, y: -6.0),
      yMoved: true
    )
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.rp2 = 16_384
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight

    // (method: SwiftTrueTypeInterpreter.GraphicsState.RoundState.Method.divide, phase: 0.0,
    // threshold: 0.34375, period: 0.359375, period45: 0.35355339013040065765380859375)
    instance.validate(except: .roundState)
  }
  */

  // Fatal arithmetic overflow in ALIGNRP
  @Test func testFuzzerArithmeticOverflowALIGNRP() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 8_192,
      maxPoints: 9_472,
      maxContours: 136,
      maxCompositePoints: 45_489,
      maxCompositeContours: 45_489,
      maxElements: 45_489,
      maxTwilightPoints: 45_489,
      maxStorage: 45_489,
      maxFunctionDefs: 45_489,
      maxInstructionDefs: 45_489,
      maxStackElements: 45_489,
      maxSizeOfInstructions: 45_489,
      maxComponentElements: 45_489,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 1_263_225_676)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 65_599),
      yStretch: .init(bitPattern: -184_547_584),
      unitsPerEm: 12_112,
      pointSize: 1_263_225_675,
      cvtScale: .init(bitPattern: 65_599),
      isRotated: false,
      isStretched: false
    )
    // warning: conversion from 0xca to HintingInstruction.MDRP not implemented, emitting literal
    // warning: conversion from 0xdb to HintingInstruction.MDRP not implemented, emitting literal
    // warning: conversion from 0xf9 to HintingInstruction.MIRP not implemented, emitting literal
    // warning: conversion from 0xff to HintingInstruction.MIRP not implemented, emitting literal
    let prep: [HintingInstruction] = [
      .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .SZP1, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV,
      .GPV, .GPV, .GPV, .SZPS, .GPV, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SPVFS, .POP,
      .SVTCA_Y, .literal(0xdb), .POP, .SPVFS, .POP, .literal(0xca), .SPVFS, .SVTCA_Y, .literal(0xff),
      .literal(0xff), .literal(0xff), .literal(0xff), .literal(0xff), .SZPS, .SPVFS, .POP, .ALIGNRP, .SRP1,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .RS, .ROUND_0, .SUB, .DELTAP3, .SUB, .SVTCA_X, .SVTCA_Y,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SSWCI, .DIV, .literal(0xff), .literal(0xff),
      .literal(0xff), .literal(0xf9), .MPPEM, .MPPEM, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
      .PUSHB([29, 116]), .DELTAP1, .NEG, .PUSHB([114, 177]), .PUSHB([96, 177]),
    ]
    instance.run(.prep, instructions: prep, failure: .arithmeticError)

    instance.expectedEngineState.cvt = [19_737_901.1875]
    instance.expectedEngineState.stack = [
      0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 16_384, 0, 16_384, 0, 16_384,
      0, 16_384, 0, 16_384, 0, 16_384,
    ]
    instance.expectedEngineState.twilightPoints[point: 0] = .init(
      scaled: .zero,
      hinted: .init(x: 0.0, y: 1.0),
      yMoved: true
    )
    instance.expectedEngineState.twilightPoints[point: 16_384] = .init(
      scaled: .zero,
      hinted: .init(x: 0.0, y: -33_554_431.0),
      yMoved: true
    )
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.rp0 = 16_384
    instance.expectedEngineState.variables.rp2 = 16_384
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }

  // Fatal arithmetic overflow in SCFS
  @Test func testFuzzerArithmeticOverflowSCFS() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 8_192,
      maxPoints: 9_472,
      maxContours: 136,
      maxCompositePoints: 45_489,
      maxCompositeContours: 45_489,
      maxElements: 45_489,
      maxTwilightPoints: 45_489,
      maxStorage: 45_489,
      maxFunctionDefs: 45_489,
      maxInstructionDefs: 45_489,
      maxStackElements: 45_489,
      maxSizeOfInstructions: 45_489,
      maxComponentElements: 45_489,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 1_263_225_675)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: -29_957),
      yStretch: .init(bitPattern: -60_404),
      unitsPerEm: 3_084,
      pointSize: 202_116_108,
      cvtScale: .init(bitPattern: -29_957),
      isRotated: false,
      isStretched: false
    )
    // warning: conversion from 0xc1 to HintingInstruction.MDRP not implemented, emitting literal
    // warning: conversion from 0xde to HintingInstruction.MDRP not implemented, emitting literal
    // warning: conversion from 0xdf to HintingInstruction.MDRP not implemented, emitting literal
    // warning: conversion from 0xea to HintingInstruction.MIRP not implemented, emitting literal
    // warning: conversion from 0xf6 to HintingInstruction.MIRP not implemented, emitting literal
    // warning: conversion from 0xff to HintingInstruction.MIRP not implemented, emitting literal
    // warning: emitting literal for unrecognized opcode 0xa2
    let prep: [HintingInstruction] = [
      .GPV, .SZPS, .GPV, .GPV, .GPV, .GFV, .GFV, .GFV, .GFV, .GFV, .GFV, .GFV, .GFV, .GFV, .SRP1, .GFV, .SLOOP,
      .SLOOP, .SLOOP, .SLOOP, .SLOOP, .FLIPOFF, .DELTAC3, .NROUND_1, .NEG, .GPV, .GPV, .GPV, .GPV, .SZP1, .GPV,
      .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .GPV, .SZPS, .GPV, .GPV, .GPV,
      .DELTAP3, .ROUND_1, .MUL, .SLOOP, .SLOOP, .SLOOP, .SLOOP, .SLOOP, .SLOOP, .SLOOP, .SLOOP, .GFV, .SVTCA_Y,
      .literal(0xf6), .literal(0xde), .literal(0xdf), .SVTCA_Y, .SVTCA_Y, .GPV, .GPV, .SCFS, .SCFS, .SCFS,
      .SVTCA_Y, .SVTCA_Y, .SCFS, .SRP1, .SVTCA_Y, .DEPTH, .POP, .literal(0xea), .MIAP_1, .GPV, .GPV, .GPV,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .literal(0xa2), .GTEQ, .DELTAC2, .DELTAP3, .ROUND_1, .ABS, .SVTCA_Y, .SVTCA_Y,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .literal(0xa2), .GTEQ, .DELTAC2, .DELTAP3,
      .SRP1, .SVTCA_Y, .DEPTH, .POP, .literal(0xea), .ROUND_1, .ABS, .NEG, .SUB, .DIV, .NROUND_0, .NEG,
      .literal(0xa2), .literal(0xa2), .literal(0xa2), .literal(0xa2), .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
      .MIAP_1, .SVTCA_Y, .literal(0xc1), .SVTCA_Y, .SVTCA_X, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SUB, .JROF,
      .literal(0xff), .SVTCA_Y, .SVTCA_Y, .POP, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SPVTCA_Y, .SVTCA_Y,
      .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT,
      .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT, .MPPEM, .MPPEM, .MPPEM, .GPV, .GPV, .GPV, .MPPEM,
      .MPPEM, .PUSHB([36, 116]), .NEG, .PUSHB([114, 177]), .PUSHB([177, 177]),
    ]
    instance.run(.prep, instructions: prep, failure: .arithmeticError)

    instance.expectedEngineState.cvt = [19_737_901.171875]
    instance.expectedEngineState.stack = [
      16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384,
      0, 16_384, 0, 16_384, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, -16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0,
      16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 0, 16_384, 16_384,
    ]
    instance.expectedEngineState.twilightPoints[point: 0] = .init(
      scaled: .zero,
      hinted: .init(x: 0.0, y: -33_554_431.0),
      yMoved: true
    )
    instance.expectedEngineState.twilightPoints[point: 16_384] = .init(
      scaled: .init(x: 0.0, y: 33_554_431.984375),
      hinted: .init(x: 0.0, y: 1.0),
      yMoved: true
    )
    instance.expectedEngineState.variables.autoFlip = false
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.loop = 0
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.rp1 = 16_384
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight
    instance.validate()
  }

  // Crash when loop-calling function containing no instructions
  @Test func testFuzzerInstructionsIndexOOB() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 8_447,
      maxPoints: 65_535,
      maxContours: 53_640,
      maxCompositePoints: 45_489,
      maxCompositeContours: 45_489,
      maxElements: 45_489,
      maxTwilightPoints: 45_489,
      maxStorage: 34_993,
      maxFunctionDefs: 45_489,
      maxInstructionDefs: 45_489,
      maxStackElements: 45_489,
      maxSizeOfInstructions: 45_489,
      maxComponentElements: 45_489,
      maxComponentDepth: 45_489
    )
    var instance = getInstance(maxp: maxp, cvtCount: 0)

    let fpgm: [HintingInstruction] = [
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .PUSHB([75, 75]), .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM,
      .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .NROUND_1, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM,
      .MPPEM, .MPPEM, .CALL, .CALL, .CALL, .CALL, .FDEF, .ENDF, .CALL, .CALL, .GETINFO, .PUSHB([177, 177]),
      .PUSHB([177, 177]), .PUSHB([177, 136]), .PUSHB([177, 177]), .PUSHB([177, 177]), .PUSHB([177, 177]),
      .PUSHB([177, 177]), .PUSHB([177, 177]), .PUSHB([77, 0]), .SVTCA_Y, .SVTCA_Y, .PUSHB([75, 75]), .MPPEM,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SFVTCA_X, .LOOPCALL, .PUSHB([177, 43]), .CALL, .CALL, .MPPEM, .MPPEM,
      .ROUND_3, .MPPEM, .MPPEM, .NEG,
    ]
    instance.run(.fpgm, instructions: fpgm)

    instance.expectedEngineState.stack = [
      0, 0, 0, 0, 75, 0, 77, 177, 177, 177, 177, 177, 177, 177, 177, 177, 177, 136, 177, 177, 177, 177, 177, 0, 0,
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 75, 75,
    ]
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.validate()
  }

  // Invalid Range creation in SHZ
  @Test func testFuzzerInvalidRangeSHZ() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 8_448,
      maxPoints: 288,
      maxContours: 37,
      maxCompositePoints: 0,
      maxCompositeContours: 34_993,
      maxElements: 45_489,
      maxTwilightPoints: 45_316,
      maxStorage: 177,
      maxFunctionDefs: 45_489,
      maxInstructionDefs: 2_653,
      maxStackElements: 9_486,
      maxSizeOfInstructions: 0,
      maxComponentElements: 0,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 0)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 64_512),
      yStretch: .init(bitPattern: 0),
      unitsPerEm: 0,
      pointSize: 0,
      cvtScale: .init(bitPattern: 64_512),
      isRotated: false,
      isStretched: false
    )
    let prep: [HintingInstruction] = []
    instance.run(.prep, instructions: prep)

    instance.setPoints(
      [
        OutlinePoint(scaled: .zero, hinted: .init(x: 0.0, y: 1.6875), onCurve: true),
        .init(scaled: .zero, hinted: .init(x: 0.0, y: 39_065.171875)),
        .init(original: .init(x: 19_532, y: 19_532), scaled: .zero, hinted: .init(x: 0.0, y: 76_952.59375)),
        .init(
          original: .init(x: 19_532, y: 19_633),
          scaled: .init(x: 1.1875, y: 20_001_073.1875),
          hinted: .init(x: 19_922_944.0, y: -6_029_311.984375)
        ),
        .init(
          original: .init(x: -1, y: -1),
          scaled: .init(x: -0.015625, y: -0.015625),
          hinted: .init(x: -0.015625, y: -15_990_784.0)
        ),
        .init(
          original: .init(x: 12, y: 1),
          scaled: .init(x: 0.0, y: -15_790_320.953125),
          hinted: .init(x: -15_790_320.953125, y: -15_790_320.953125),
          onCurve: true,
          xMoved: true
        ),
        .init(
          original: .init(x: 6, y: 0),
          scaled: .init(x: 0.953125, y: 15_929_103.046875),
          hinted: .init(x: -15_790_320.953125, y: -15_790_320.953125),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: -15_421, y: -15_421),
          scaled: .init(x: -15_790_320.953125, y: -15_790_320.953125),
          hinted: .init(x: -15_728_640.015625, y: -0.015625),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: -256, y: 25_420),
          scaled: .init(x: 20_001_073.1875, y: 244.0),
          hinted: .init(x: 0.0, y: 0.1875),
          xMoved: true
        ),
      ],
      forZone: .glyph
    )
    instance.setContours([4..<9], forZone: .glyph)
    let glyf: [HintingInstruction] = [
      .MPPEM, .FLIPOFF, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y,
      .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_Y, .IUP_X,
      .SHZ_0, .IP, .SHZ_0, .IUP_Y, .SHZ_0, .SHC_1, .IP, .SHPIX, .SHC_0, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
    ]
    instance.run(.glyf, instructions: glyf, failure: .noSuchContour)

    instance.expectedEngineState.stack = [1]
    instance.expectedEngineState.glyphPoints[point: 0] = .init(scaled: .zero, onCurve: true)
    instance.expectedEngineState.glyphPoints[point: 1] = .init(scaled: .zero, xMoved: true)
    instance.expectedEngineState.glyphPoints[point: 2] = .init(original: .init(x: 19_532, y: 19_532), scaled: .zero)
    instance.expectedEngineState.glyphPoints[point: 3] = .init(
      original: .init(x: 19_532, y: 19_633),
      scaled: .init(x: 1.1875, y: 20_001_073.1875)
    )
    instance.expectedEngineState.glyphPoints[point: 4] = .init(
      original: .init(x: -1, y: -1),
      scaled: .init(x: -0.015625, y: -0.015625)
    )
    instance.expectedEngineState.glyphPoints[point: 5] = .init(
      original: .init(x: 12, y: 1),
      scaled: .init(x: 0.0, y: -15_790_320.953125),
      onCurve: true,
      xMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 6] = .init(
      original: .init(x: 6, y: 0),
      scaled: .init(x: 0.953125, y: 15_929_103.046875),
      onCurve: true,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 7] = .init(
      original: .init(x: -15_421, y: -15_421),
      scaled: .init(x: -15_790_320.953125, y: -15_790_320.953125),
      onCurve: true,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 8] = .init(
      original: .init(x: -256, y: 25_420),
      scaled: .init(x: 20_001_073.1875, y: 244.0),
      xMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 9] = .init(
      original: .init(x: -15_421, y: 4_999),
      scaled: .init(x: -15_790_320.953125, y: 2_105_376.109375)
    )
    instance.expectedEngineState.glyphPoints[point: 10] = .init(
      original: .init(x: 19_532, y: 4_999),
      scaled: .init(x: 20_001_073.1875, y: 2_105_376.109375)
    )
    instance.expectedEngineState.glyphPoints[point: 11] = .init(
      original: .init(x: 2_055, y: 25_420),
      scaled: .init(x: 2_105_376.109375, y: 20_001_073.1875)
    )
    instance.expectedEngineState.glyphPoints[point: 12] = .init(
      original: .init(x: 2_055, y: -15_421),
      scaled: .init(x: 2_105_376.109375, y: -15_790_320.953125)
    )
    instance.expectedEngineState.glyphPoints[point: 13] = .init(
      original: .init(x: -15_421, y: 4_999),
      scaled: .init(x: -15_790_320.953125, y: 2_105_376.109375),
      hinted: .init(x: -15_790_320.953125, y: -7_956_915.703125)
    )
    instance.expectedEngineState.glyphPoints[point: 14] = .init(
      original: .init(x: 19_532, y: 4_999),
      scaled: .init(x: 20_001_073.1875, y: 2_105_376.109375),
      hinted: .init(x: 19_922_944.0, y: -7_956_915.703125)
    )
    instance.expectedEngineState.glyphPoints[point: 15] = .init(
      original: .init(x: 2_055, y: 25_420),
      scaled: .init(x: 2_105_376.109375, y: 20_001_073.1875),
      hinted: .init(x: 2_066_311.515625, y: 76_952.59375)
    )
    instance.expectedEngineState.glyphPoints[point: 16] = .init(
      original: .init(x: 2_055, y: -15_421),
      scaled: .init(x: 2_105_376.109375, y: -15_790_320.953125),
      hinted: .init(x: 2_066_311.515625, y: -15_990_784.0)
    )
    instance.expectedEngineState.variables.autoFlip = false
    instance.validate()
  }

  @Test func testFuzzerArithmeticOverflowIUP3() {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 84,
      maxPoints: 21_588,
      maxContours: 21_572,
      maxCompositePoints: 16_452,
      maxCompositeContours: 256,
      maxElements: 17_492,
      maxTwilightPoints: 5_204,
      maxStorage: 11_604,
      maxFunctionDefs: 21_588,
      maxInstructionDefs: 21_588,
      maxStackElements: 17_492,
      maxSizeOfInstructions: 146,
      maxComponentElements: 0,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 0)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 47),
      yStretch: .init(bitPattern: 0),
      unitsPerEm: 0,
      pointSize: 0,
      cvtScale: .init(bitPattern: 47),
      isRotated: false,
      isStretched: false
    )
    let prep: [HintingInstruction] = []
    instance.run(.prep, instructions: prep)

    instance.setPoints(
      [
        OutlinePoint(scaled: .zero), .init(scaled: .init(x: 512.5, y: 0.0), hinted: .init(x: 0.0, y: 43_008.0)),
        .init(
          scaled: .init(x: 32_051_605.59375, y: 25_548_209.8125),
          hinted: .init(x: 19_249_553.640625, y: 182_986.78125),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: -19_790, y: -19_790),
          scaled: .init(x: -20_264_245.21875, y: 707_274.78125),
          hinted: .init(x: -20_256_640.0, y: 182_986.78125),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: -19_790, y: -19_790),
          scaled: .init(x: -20_447_232.0, y: -20_264_245.21875),
          hinted: .init(x: 5_163_281.0, y: 17_826_817.0625),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: 11_604, y: 21_588),
          scaled: .init(x: 22_106_385.3125, y: -28_835_840.0),
          hinted: .init(x: 136_192.0, y: 0.0)
        ),
        .init(scaled: .init(x: 0.0, y: 17_156_553.515625), hinted: .init(x: 31_719_424.0, y: 0.0)),
        .init(scaled: .zero),
        .init(scaled: .zero, hinted: .init(x: 41_984.0, y: 0.0)),
      ],
      forZone: .glyph
    )
    instance.setContours([0..<7], forZone: .glyph)
    // warning: conversion from 0xe8 to HintingInstruction.MIRP not implemented, emitting literal
    let glyf: [HintingInstruction] = [
      .PUSHB([178, 178, 18]), .PUSHB([178, 178, 178]), .PUSHB([178, 178, 2]), .PUSHB([178, 178, 178]),
      .PUSHW([0, 178, -19_790]), .PUSHB([0, 0, 0]), .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .NROUND_1, .SVTCA_Y, .ADD,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .FLIPON, .SVTCA_Y,
      .SVTCA_Y, .SVTCA_Y, .SHP_1, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y,
      .GPV, .SVTCA_Y, .MPS, .MPS, .literal(0xe8), .MPS, .MPS, .MPS, .NOT, .MPS, .MPS, .MPS, .MPS, .GC_1, .MPS,
      .SCFS, .GC_1, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .MPS, .SVTCA_X, .SVTCA_Y,
      .SVTCA_Y, .MIAP_1, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .DEPTH, .SVTCA_Y, .SVTCA_Y, .WCVTP, .NEQ, .NROUND_3,
      .S45ROUND, .GT, .SUB, .GT, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .NROUND_2,
      .IUP_Y, .PUSHW([-16_449, -16_486, -24_833, -65, -16_449, 407, 0, 0]), .SVTCA_Y, .SVTCA_Y, .AA, .SVTCA_Y,
      .SVTCA_Y, .JROT, .JROT, .JROT, .JROT, .INSTCTRL, .INSTCTRL, .DELTAP3, .PUSHB([138, 139]), .NEG, .DELTAP3,
      .ROUND_1, .MUL, .INSTCTRL, .S45ROUND, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .MIN, .INSTCTRL,
      .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL,
      .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL, .INSTCTRL,
      .PUSHB([229, 178, 178]), .PUSHB([84, 191, 68]), .EQ, .SVTCA_Y, .GETDATA, .SVTCA_Y,
    ]
    instance.run(.glyf, instructions: glyf, failure: .stackUnderflow)

    instance.expectedEngineState.cvt = [0.09375]
    instance.expectedEngineState.glyphPoints[point: 0] = .init(scaled: .zero, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1] = .init(scaled: .init(x: 512.5, y: 0.0))
    instance.expectedEngineState.glyphPoints[point: 2] = .init(
      scaled: .init(x: 32_051_605.59375, y: 25_548_209.8125),
      onCurve: true,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 3] = .init(
      original: .init(x: -19_790, y: -19_790),
      scaled: .init(x: -20_264_245.21875, y: 707_274.78125),
      onCurve: true,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 4] = .init(
      original: .init(x: -19_790, y: -19_790),
      scaled: .init(x: -20_447_232.0, y: -20_264_245.21875),
      onCurve: true,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 5] = .init(
      original: .init(x: 11_604, y: 21_588),
      scaled: .init(x: 22_106_385.3125, y: -28_835_840.0)
    )
    instance.expectedEngineState.glyphPoints[point: 6] = .init(scaled: .init(x: 0.0, y: 17_156_553.515625))
    instance.expectedEngineState.glyphPoints[point: 9] = .init(
      original: .init(x: -19_790, y: 899),
      scaled: .init(x: -20_447_232.0, y: -1_643_815.09375)
    )
    instance.expectedEngineState.glyphPoints[point: 10] = .init(
      original: .init(x: 11_604, y: 899),
      scaled: .init(x: 32_051_605.59375, y: -1_643_815.09375)
    )
    instance.expectedEngineState.glyphPoints[point: 11] = .init(
      original: .init(x: -4_093, y: 21_588),
      scaled: .init(x: 5_802_186.796875, y: 25_548_209.8125)
    )
    instance.expectedEngineState.glyphPoints[point: 12] = .init(
      original: .init(x: -4_093, y: -19_790),
      scaled: .init(x: 5_802_186.796875, y: -28_835_840.0)
    )
    instance.expectedEngineState.glyphPoints[point: 13] = .init(
      original: .init(x: -19_790, y: 899),
      scaled: .init(x: -20_447_232.0, y: -1_643_815.09375),
      hinted: .init(x: -20_256_640.0, y: 8_913_408.53125)
    )
    instance.expectedEngineState.glyphPoints[point: 14] = .init(
      original: .init(x: 11_604, y: 899),
      scaled: .init(x: 32_051_605.59375, y: -1_643_815.09375),
      hinted: .init(x: 31_719_424.0, y: 8_913_408.53125)
    )
    instance.expectedEngineState.glyphPoints[point: 15] = .init(
      original: .init(x: -4_093, y: 21_588),
      scaled: .init(x: 5_802_186.796875, y: 25_548_209.8125),
      hinted: .init(x: 5_731_392.0, y: 17_826_817.0625)
    )
    instance.expectedEngineState.glyphPoints[point: 16] = .init(
      original: .init(x: -4_093, y: -19_790),
      scaled: .init(x: 5_802_186.796875, y: -28_835_840.0),
      hinted: .init(x: 5_731_392.0, y: 0.0)
    )
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis

    // (method: SwiftTrueTypeInterpreter.GraphicsState.RoundState.Method.mask, phase: 0.0,
    // threshold: 0.5, period: 1.0, period45: 0.0), found RoundState(method:
    // SwiftTrueTypeInterpreter.GraphicsState.RoundState.Method.divide, phase: 0.0,
    // threshold: 0.34375, period: 0.359375, period45: 0.35355339013040065765380859375)
    instance.validate(except: .roundState)
  }

  @Test func testFuzzerArithmeticOverflowMDAP() {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 84,
      maxPoints: 21_588,
      maxContours: 21_572,
      maxCompositePoints: 17_476,
      maxCompositeContours: 256,
      maxElements: 17_492,
      maxTwilightPoints: 21_588,
      maxStorage: 11_604,
      maxFunctionDefs: 21_588,
      maxInstructionDefs: 595,
      maxStackElements: 17_492,
      maxSizeOfInstructions: 146,
      maxComponentElements: 0,
      maxComponentDepth: 256
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 524_288)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 1_024),
      yStretch: .init(bitPattern: -2_030_043_137),
      unitsPerEm: -1,
      pointSize: 0,
      cvtScale: .init(bitPattern: 1_024),
      isRotated: false,
      isStretched: false
    )
    let prep: [HintingInstruction] = [
      0, 0, 0, 0, 191, 191, 191, 76, 17, 17, 17, 17, 17, 17, 127, 0, 12, 8, 47, 76, 76, 76, 76, 93, 76, 76, 96,
      76, 76, 76, 76, 76, 76, 76, 76, 105, 103, 122, 104, 32, 108, 111, 119, 22, 233, 0, 0, 0, 0, 0, 0, 0, 191,
      191, 191, 191, 154, 158, 255, 255, 191, 191, 191, 191, 12, 17, 17, 17, 17, 17, 17, 127, 120, 120, 120, 18,
      1, 0, 0,
    ].map { opcode in .literal(.init(opcode)) }
    instance.run(.prep, instructions: prep, failure: .arithmeticError)

    instance.expectedEngineState.cvt = [8_192.0]
    instance.expectedEngineState.stack = [
      0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 19_532, 2_095, 12, 4_479, 4_369, 4_369, 19_473, -16_449,
    ]
    instance.expectedEngineState.twilightPoints[point: 0] = .init(
      scaled: .zero,
      hinted: .init(x: -33_554_432.0, y: -33_554_432.0),
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.variables.freedomVector = .init(x: 1.0, y: 0.0)
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight

    // (method: SwiftTrueTypeInterpreter.GraphicsState.RoundState.Method.divide, phase: 0.0,
    // threshold: 0.34375, period: 0.359375, period45: 0.35355339013040065765380859375)
    instance.validate(except: .roundState)
  }

  // Caught during development
  @Test func testFuzzerIUPOverflow() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 84,
      maxPoints: 21_597,
      maxContours: 21_572,
      maxCompositePoints: 17_476,
      maxCompositeContours: 256,
      maxElements: 17_492,
      maxTwilightPoints: 21_588,
      maxStorage: 11_628,
      maxFunctionDefs: 28_535,
      maxInstructionDefs: 25_970,
      maxStackElements: 256,
      maxSizeOfInstructions: 25,
      maxComponentElements: 159,
      maxComponentDepth: 512
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 524_288)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 8_192),
      yStretch: .init(bitPattern: 2_046_820_352),
      unitsPerEm: 0,
      pointSize: 0,
      cvtScale: .init(bitPattern: 2_046_820_352),
      isRotated: false,
      isStretched: false
    )
    let prep: [HintingInstruction] = [
      .SVTCA_Y, .RTDG, .SVTCA_Y, .SVTCA_Y, .GPV, .SVTCA_Y, .MPS, .MPS, .MPS, .MPS, .DELTAP1,
      .PUSHB([179, 159, 1, 0, 76, 76]), .MPS, .MPS, .ROUND_0, .DUP, .CEILING, .SVTCA_Y, .SFVTCA_X, .ROFF,
      .S45ROUND, .NROUND_0, .NROUND_3, .SZPS, .literal(0xe1), .SVTCA_Y, .SHP_0, .IUP_X, .SVTCA_Y, .ISECT,
      .SFVTL_1, .SVTCA_Y, .PUSHW([-16_449, -16_486, -3_329, -65, -16_449, -16_628, 4_369, 4_369]), .SRP1, .SRP1,
      .AA, .SVTCA_Y, .SVTCA_Y,
    ]
    instance.run(.prep, instructions: prep)

    instance.expectedEngineState.cvt = [8_192.0]
    instance.expectedEngineState.stack = [-16_449, -65, -3_329, -16_486, -16_449, 16_384, 0]
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.rp1 = 4_369
    instance.expectedEngineState.variables.rp2 = 76
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight

    /* This test mostly validates that fuzzer-discovered arithmetic overflows in IUP remain non-fatal.
     * The expected state above helps ensure that IUP_X actually gets executed—in the past a parameter validation
     * regression in DELTAP caused this test to quietly stop providing the coverage it is intended to provide.
     *
     * Otherwise, the effects of the overflow are far-reaching (the twilight zone is very large)
     * and not critical to maintain.
     */
    instance.validate(except: [.roundState, .twilightPoints])
  }

  @Test func testFuzzerIUPOverflow2() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 84,
      maxPoints: 21_588,
      maxContours: 21_504,
      maxCompositePoints: 96,
      maxCompositeContours: 13,
      maxElements: 3_341,
      maxTwilightPoints: 3_341,
      maxStorage: 3_341,
      maxFunctionDefs: 3_341,
      maxInstructionDefs: 3_341,
      maxStackElements: 3_328,
      maxSizeOfInstructions: 25,
      maxComponentElements: 159,
      maxComponentDepth: 512
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 268_959_744)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 8_192),
      yStretch: .init(bitPattern: 2_046_835_200),
      unitsPerEm: 0,
      pointSize: 0,
      cvtScale: .init(bitPattern: 2_046_835_200),
      isRotated: false,
      isStretched: false
    )
    // warning: conversion from 0xe1 to HintingInstruction.MIRP not implemented, emitting literal
    // warning: conversion from 0xfa to HintingInstruction.MIRP not implemented, emitting literal
    let prep: [HintingInstruction] = [
      .SVTCA_Y, .RTDG, .SVTCA_Y, .GPV, .SVTCA_Y, .MPS, .MPS, .MPS, .MPS, .DELTAP1,
      .PUSHB([179, 159, 1, 0, 76, 76]), .MPS, .MPS, .MPS, .MPS, .CEILING, .ROUND_1, .ROUND_0, .DUP, .FLOOR,
      .SVTCA_Y, .SFVTCA_X, .ROFF, .S45ROUND, .NROUND_0, .NROUND_3, .SZPS, .literal(0xe1), .SVTCA_Y, .IUP_Y,
    ]
    instance.run(.prep, instructions: prep)

    instance.expectedEngineState.cvt = [4_202_496.0]
    instance.expectedEngineState.stack = [0, 76, 76, 0, 1, 159, 179, 0, 0, 0, 16_384, 0]
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.zp0 = .twilight
    instance.expectedEngineState.variables.zp1 = .twilight
    instance.expectedEngineState.variables.zp2 = .twilight

    /* This test mostly validates that fuzzer-discovered arithmetic overflows in IUP remain non-fatal.
     * The expected state above helps ensure that IUP_Y actually gets executed—in the past a parameter validation
     * regression in DELTAP caused this test to quietly stop providing the coverage it is intended to provide.
     *
     * Otherwise, the effects of the overflow are far-reaching (the twilight zone is very large)
     * and not critical to maintain.
     */
    instance.validate(except: [.roundState, .twilightPoints])
  }

#if arch(arm64)
  // This test includes Int literals that don't fit in 32-bits but Swift doesn't have
  // a compile-time flag for LP64 so arm64 will do for now
  @Test func testFuzzerCollectionCrashIUP() {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 65_371,
      maxPoints: 65_290,
      maxContours: 0,
      maxCompositePoints: 8_960,
      maxCompositeContours: 151,
      maxElements: 38_807,
      maxTwilightPoints: 0,
      maxStorage: 0,
      maxFunctionDefs: 56_946,
      maxInstructionDefs: 18_804,
      maxStackElements: 38_944,
      maxSizeOfInstructions: 25_953,
      maxComponentElements: 0,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 0)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 0),
      yStretch: .init(bitPattern: 65_583),
      unitsPerEm: 0,
      pointSize: 7_995_392,
      cvtScale: .init(bitPattern: 65_583),
      isRotated: false,
      isStretched: false
    )
    let prep: [HintingInstruction] = []
    instance.run(.prep, instructions: prep)

    instance.setPoints(
      [
        OutlinePoint(scaled: .zero),
        .init(
          scaled: .init(x: 0.0, y: 301.171875),
          hinted: .init(x: 19_737_901.171875, y: 19_737_901.171875),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: 19_275, y: 19_275),
          scaled: .init(x: 19_737_901.171875, y: 19_737_902.75),
          hinted: .init(x: -19_737_902.828125, y: 19_738_029.171875),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: 19_275, y: 19_275),
          scaled: .init(x: 19_737_901.171875, y: 19_737_901.171875),
          hinted: .init(x: 19_737_901.171875, y: 19_723_565.15625),
          onCurve: true
        ),
        .init(scaled: .zero, hinted: .init(x: 0.0, y: -4.0), onCurve: true),
        .init(
          scaled: .init(x: 261_121.3125, y: 31_843_813.890625),
          hinted: .init(x: 4_804_945.3125, y: 17_895_697.0625),
          onCurve: true,
          xMoved: true,
          yMoved: true
        ),
        .init(
          original: .init(x: -1, y: -256),
          scaled: .init(x: 219_138.0, y: 384.0),
          hinted: .init(x: 1_450_712.0, y: 0.0)
        ),
        .init(scaled: .init(x: 0.0, y: 19_434_496.0), hinted: .init(x: 0.0625, y: 0.0)),
        .init(scaled: .init(x: 2_048.0, y: 93_457.3125), hinted: .init(x: 149_504.0, y: 2.28125)),
      ],
      forZone: .glyph
    )
    instance.setContours([84..<256], forZone: .glyph)
    let glyf: [HintingInstruction] = [
      .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .NEQ, .MPPEM, .MPPEM, .IUP_X, .MPPEM, .MPPEM, .MPPEM, .ROUND_3,
      .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .MPPEM, .ISECT, .ISECT, .ISECT, .ISECT, .ISECT,
      .SVTCA_Y, .SVTCA_Y, .PUSHB([73, 116]), .NEG, .DELTAP3, .SUB, .SVTCA_Y, .GTEQ,
    ]
    instance.run(.glyf, instructions: glyf, failure: .stackUnderflow)

    instance.expectedEngineState.glyphPoints[point: 0] = .init(scaled: .zero, xMoved: true, yMoved: true)
    instance.expectedEngineState.glyphPoints[point: 1] = .init(
      scaled: .init(x: 0.0, y: 301.171875),
      onCurve: true,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 2] = .init(
      original: .init(x: 19_275, y: 19_275),
      scaled: .init(x: 19_737_901.171875, y: 19_737_902.75),
      onCurve: true,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 3] = .init(
      original: .init(x: 19_275, y: 19_275),
      scaled: .init(x: 19_737_901.171875, y: 19_737_901.171875),
      onCurve: true
    )
    instance.expectedEngineState.glyphPoints[point: 4] = .init(scaled: .zero, onCurve: true)
    instance.expectedEngineState.glyphPoints[point: 5] = .init(
      scaled: .init(x: 261_121.3125, y: 31_843_813.890625),
      onCurve: true,
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.glyphPoints[point: 6] = .init(
      original: .init(x: -1, y: -256),
      scaled: .init(x: 219_138.0, y: 384.0)
    )
    instance.expectedEngineState.glyphPoints[point: 7] = .init(scaled: .init(x: 0.0, y: 19_434_496.0))
    instance.expectedEngineState.glyphPoints[point: 8] = .init(scaled: .init(x: 2_048.0, y: 93_457.3125))
    instance.expectedEngineState.glyphPoints[point: 9] = .init(
      original: .init(x: -1, y: 9_509),
      scaled: .init(x: 0.0, y: 15_921_906.9375)
    )
    instance.expectedEngineState.glyphPoints[point: 10] = .init(
      original: .init(x: 19_275, y: 9_509),
      scaled: .init(x: 19_737_901.171875, y: 15_921_906.9375)
    )
    instance.expectedEngineState.glyphPoints[point: 11] = .init(
      original: .init(x: 9_637, y: 19_275),
      scaled: .init(x: 9_868_950.578125, y: 31_843_813.890625)
    )
    instance.expectedEngineState.glyphPoints[point: 12] = .init(
      original: .init(x: 9_637, y: -256),
      scaled: .init(x: 9_868_950.578125, y: 0.0)
    )
    instance.expectedEngineState.glyphPoints[point: 13] = .init(
      original: .init(x: -1, y: 9_509),
      scaled: .init(x: 0.0, y: 15_921_906.9375),
      hinted: .init(x: -19_737_902.828125, y: 9_869_012.578125)
    )
    instance.expectedEngineState.glyphPoints[point: 14] = .init(
      original: .init(x: 19_275, y: 9_509),
      scaled: .init(x: 19_737_901.171875, y: 15_921_906.9375),
      hinted: .init(x: 19_737_901.171875, y: 9_869_012.578125)
    )
    instance.expectedEngineState.glyphPoints[point: 15] = .init(
      original: .init(x: 9_637, y: 19_275),
      scaled: .init(x: 9_868_950.578125, y: 31_843_813.890625),
      hinted: .init(x: -0.828125, y: 19_738_029.171875)
    )
    instance.expectedEngineState.glyphPoints[point: 16] = .init(
      original: .init(x: 9_637, y: -256),
      scaled: .init(x: 9_868_950.578125, y: 0.0),
      hinted: .init(x: -0.828125, y: -4.0)
    )
    instance.validate()
  }
#endif

  // MARK: - Coverage

  // The following test cases provide basic coverage for difficult-to-reach code paths
  // that involve exceptional conditions to show that the interpreter has reasonable behaviour
  // in conditions like "an arithmetic operation overflows" or "a would-be divisor is zero".

  @Test func testFuzzerCoverageISECT1() throws {
    let maxp = sfntMaxProfileTable(
      version: 65_536,
      numGlyphs: 2_170,
      maxPoints: 0,
      maxContours: 0,
      maxCompositePoints: 0,
      maxCompositeContours: 0,
      maxElements: 83,
      maxTwilightPoints: 29_810,
      maxStorage: 26_980,
      maxFunctionDefs: 25_957,
      maxInstructionDefs: 25_089,
      maxStackElements: 0,
      maxSizeOfInstructions: 9_324,
      maxComponentElements: 25_856,
      maxComponentDepth: 0
    )
    var instance = getInstance(maxp: maxp, cvtCount: 1)

    instance.setVariationCoord([0.00128173828125, 0.0])

    let fpgm: [HintingInstruction] = []
    instance.run(.fpgm, instructions: fpgm)

    instance.setCVT([.init(bitPattern: 122)])
    instance.setScaleFactors(
      xStretch: .init(bitPattern: 0),
      yStretch: .init(bitPattern: 0),
      unitsPerEm: 0,
      pointSize: 35,
      cvtScale: .init(bitPattern: 0),
      isRotated: false,
      isStretched: false
    )
    // warning: conversion from 0xe5 to HintingInstruction.MIRP not implemented, emitting literal
    // warning: conversion from 0xf1 to HintingInstruction.MIRP not implemented, emitting literal
    // warning: conversion from 0xf0 to HintingInstruction.MIRP not implemented, emitting literal
    // warning: conversion from 0xff to HintingInstruction.MIRP not implemented, emitting literal
    let prep: [HintingInstruction] = [
      .PUSHB([178, 178, 171, 77]), .FLIPON, .GPV, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SZPS, .SVTCA_Y,
      .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .SVTCA_Y, .GETVARIATION, .SVTCA_Y, .GETVARIATION, .GETVARIATION,
      .SCANTYPE, .GETVARIATION, .GETVARIATION, .GETVARIATION, .GETVARIATION, .GETVARIATION, .GETVARIATION,
      .GETVARIATION, .GETVARIATION, .GETVARIATION, .GETVARIATION, .literal(0xe5), .ISECT, .ISECT, .literal(0xf1),
      .literal(0xf0), .literal(0xf0), .SVTCA_X, .PUSHB([240, 0, 145, 145]), .GETVARIATION, .SCANTYPE,
      .GETVARIATION, .GETVARIATION, .GETVARIATION, .GETVARIATION, .RTDG, .GETVARIATION, .GETVARIATION,
      .GETVARIATION, .GETVARIATION, .literal(0xff), .literal(0xff), .literal(0xff), .literal(0xff),
      .literal(0xff), .literal(0xff), .literal(0xff), .literal(0xff), .PUSHB([145, 229]), .ISECT, .ISECT,
      .literal(0xff), .SZPS, .SZPS, .SVTCA_Y, .SVTCA_Y, .SFVTL_0, .SFVTL_0, .GFV,
    ]
    instance.run(.prep, instructions: prep, failure: .invalidAccessToGlyphZone)

    instance.expectedEngineState.cvt = [1.90625]
    instance.expectedEngineState.stack = [171, 178, 178]
    instance.expectedEngineState.twilightPoints[point: 0] = .init(
      scaled: .zero,
      hinted: .init(x: 0.0, y: 31_232.0),
      xMoved: true,
      yMoved: true
    )
    // The code path this test is specifically interested in testing operates on twilight zone point 21
    instance.expectedEngineState.twilightPoints[point: 21] = .init(
      scaled: .init(x: 562_176.0, y: 187_392.0),
      hinted: .init(x: 62_464.0, y: 31_232.0),
      xMoved: true,
      yMoved: true
    )
    instance.expectedEngineState.twilightPoints[point: 145] = .init(scaled: .zero, xMoved: true, yMoved: true)
    instance.expectedEngineState.variables.freedomVector = .y_axis
    instance.expectedEngineState.variables.projectionVector = .y_axis
    instance.expectedEngineState.variables.rp0 = 21
    instance.expectedEngineState.variables.rp1 = 21
    instance.expectedEngineState.variables.rp2 = 21

    // (method: SwiftTrueTypeInterpreter.GraphicsState.RoundState.Method.mask, phase: 0.0,
    // threshold: 0.5, period: 1.0, period45: 0.0), found RoundState(method:
    // SwiftTrueTypeInterpreter.GraphicsState.RoundState.Method.mask, phase: 0.0,
    // threshold: 0.25, period: 0.5, period45: 0.0)
    instance.validate(except: .roundState)
  }
}
