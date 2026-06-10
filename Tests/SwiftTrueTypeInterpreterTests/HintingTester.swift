import SwiftTrueTypeInterpreter
import Testing

enum HintingProgram {
  case fpgm
  case prep
  case glyf

  static let all: [Self] = [.fpgm, .prep, .glyf]

  static func dontCare() -> Self {
    [.fpgm, .prep, glyf].randomElement()!
  }

  // For example, tests that need to define functions
  static func notGlyf() -> Self {
    [.fpgm, .prep].randomElement()!
  }

  // For example, tests that need twilight zone points
  static func notFpgm() -> Self {
    [.prep, glyf].randomElement()!
  }
}

struct StateComponentOptions: OptionSet, Equatable {
  let rawValue: Int

  static let cvt = Self(rawValue: 1 << 0)
  static let stack = Self(rawValue: 1 << 1)
  static let storage = Self(rawValue: 1 << 2)
  static let glyphPoints = Self(rawValue: 1 << 3)
  static let twilightPoints = Self(rawValue: 1 << 4)
  static let points: Self = [.glyphPoints, .twilightPoints]

  static let maxp = Self(rawValue: 1 << 5)

  static let autoFlip = Self(rawValue: 1 << 6)
  static let controlValueCutIn = Self(rawValue: 1 << 7)
  static let deltaBase = Self(rawValue: 1 << 8)
  static let deltaShift = Self(rawValue: 1 << 9)
  static let dualProjectionVector = Self(rawValue: 1 << 10)
  static let freedomVector = Self(rawValue: 1 << 11)
  static let instructControl = Self(rawValue: 1 << 12)
  static let loop = Self(rawValue: 1 << 13)
  static let minimumDistance = Self(rawValue: 1 << 14)
  static let projectionVector = Self(rawValue: 1 << 15)
  static let roundState = Self(rawValue: 1 << 16)
  static let referencePoints = Self(rawValue: 1 << 17)
  static let scanControl = Self(rawValue: 1 << 18)
  static let singleWidthCutIn = Self(rawValue: 1 << 19)
  static let singleWidthValue = Self(rawValue: 1 << 20)
  static let zonePointers = Self(rawValue: 1 << 21)

  static let all = Self(rawValue: ~0)
}

struct EngineStateVariables: Equatable {
  var autoFlip: Bool
  var controlValueCutIn: F26Dot6
  var deltaBase: Int16
  var deltaShift: Int16
  var dualProjectionVector: FixedVector<F2Dot14>?
  var freedomVector: FixedVector<F2Dot14>
  var loop: Int32
  var minimumDistance: F26Dot6
  var projectionVector: FixedVector<F2Dot14>
  var roundState: RoundState
  var rp0: Int
  var rp1: Int
  var rp2: Int
  var instructControl: SwiftTrueTypeInterpreter.GraphicsState.InstructControl
  var scanControl: SwiftTrueTypeInterpreter.GraphicsState.ScanControl
  var singleWidthCutIn: F26Dot6
  var singleWidthValue: F26Dot6
  var zp0: SwiftTrueTypeInterpreter.Zone.ZoneType
  var zp1: SwiftTrueTypeInterpreter.Zone.ZoneType
  var zp2: SwiftTrueTypeInterpreter.Zone.ZoneType
}

struct EngineState: Equatable {
  var variables: EngineStateVariables
  var twilightPoints: EngineStatePointZone
  var glyphPoints: EngineStatePointZone
  var stack: [Int32]
  var storage: [Int32]
  var cvt: [F26Dot6]

  mutating func assign(property: EngineStateProperty) {
    switch property.rawValue {
    case let .stack(array):
      self.stack = array
    case let .point(zone: zone, index: index, value: value):
      switch zone {
      case .glyph:
        glyphPoints[point: index] = value
      case .twilight: preconditionFailure()
      }
    case let .variableInt32(kp, value):
      variables[keyPath: kp] = value
    case let .variableInt(kp, value):
      variables[keyPath: kp] = value
    case let .variableZoneType(kp, value):
      variables[keyPath: kp] = value
    }
  }
}

struct EngineStatePointZone: Equatable {
  let zoneType: ZoneType
  var points: [OutlinePoint]

  var count: Int { points.count }

  init(zoneType: ZoneType, points: [OutlinePoint]) {
    self.zoneType = zoneType
    self.points = points
  }

  subscript(point index: Int) -> OutlinePoint {
    get { points[index] }
    set { points[index] = newValue }
  }
}

private enum EngineStateProperties {
  case point(zone: ZoneType, index: Int, value: OutlinePoint)
  case stack([Int32])
  case variableInt(WritableKeyPath<EngineStateVariables, Int>, Int)
  case variableInt32(WritableKeyPath<EngineStateVariables, Int32>, Int32)
  case variableZoneType(
    WritableKeyPath<EngineStateVariables, SwiftTrueTypeInterpreter.Zone.ZoneType>,
    SwiftTrueTypeInterpreter.Zone.ZoneType
  )
}

struct EngineStateProperty {
  fileprivate var rawValue: EngineStateProperties

  private init(rawValue: EngineStateProperties) {
    self.rawValue = rawValue
  }

  static func stack(_ value: [Int32]) -> Self {
    .init(rawValue: .stack(value))
  }

  static func glyphPoint(_ point: OutlinePoint, at index: Int) -> Self {
    .init(rawValue: .point(zone: .glyph, index: index, value: point))
  }

  static func variable(_ keyPath: WritableKeyPath<EngineStateVariables, Int32>, _ value: Int32) -> Self {
    .init(rawValue: .variableInt32(keyPath, value))
  }

  static func variable(_ keyPath: WritableKeyPath<EngineStateVariables, Int>, _ value: Int) -> Self {
    .init(rawValue: .variableInt(keyPath, value))
  }

  static func variable(
    _ keyPath: WritableKeyPath<EngineStateVariables, SwiftTrueTypeInterpreter.Zone.ZoneType>,
    _ value: SwiftTrueTypeInterpreter.Zone.ZoneType
  ) -> Self {
    .init(rawValue: .variableZoneType(keyPath, value))
  }
}

struct HintingTester: ~Copyable {
  private var hasSetScaleFactors: Bool = false
  var interface: HintingTestInterface
  var expectedEngineState: EngineState!
  var didValidate: Bool = false
  var needsValidate: Bool = false

  init(interface: HintingTestInterface) {
    self.interface = interface
  }

  deinit {
    if needsValidate, !didValidate {
      Issue.record("nobody called validate()")
    }
  }

  func engineState() -> EngineState {
    interface.engineState()
  }

  mutating func run(
    _ program: HintingProgram? = .dontCare(),
    instructions: [HintingInstruction],
    unscaledOutlineIsWrong: Bool? = nil,
    failure: InterpreterError? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    assert(
      unscaledOutlineIsWrong == nil || program == .glyf,
      "unscaledOutlineIsWrong requires specifying a .glyf program"
    )
    assert(
      !hasSetScaleFactors || program != .fpgm,
      "scale factors should not be set before .fpgm, did you mean to specify `notFpgm()`?"
    )

    let unscaledOutlineIsWrong = unscaledOutlineIsWrong ?? false
    let program = program ?? .dontCare()
    if !hasSetScaleFactors, program != .fpgm {
      self.setScaleFactors()
    }

    if expectedEngineState == nil {
      expectedEngineState = interface.engineState()
    }

    interface.run(
      program,
      instructions: instructions,
      unscaledOutlineIsWrong: unscaledOutlineIsWrong,
      failure: failure,
      sourceLocation: sourceLocation
    )
    needsValidate = true
    didValidate = false
  }

  mutating func run(
    _ program: HintingProgram? = nil,
    instructions: HintingInstruction...,
    unscaledOutlineIsWrong: Bool? = nil,
    failure: InterpreterError? = nil,
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    self.run(
      program,
      instructions: instructions,
      unscaledOutlineIsWrong: unscaledOutlineIsWrong,
      failure: failure,
      sourceLocation: sourceLocation
    )
  }

  mutating func setCVT(_ cvt: [F26Dot6]) {
    interface.setCVT(cvt)
  }

  // points
  mutating func setPoints(
    hinted: [OutlineCoord] = [],
    scaled: [OutlineCoord],
    original: [UnscaledCoord] = [],
    forZone zone: ZoneType
  ) {
    assert(hinted.isEmpty || scaled.count == hinted.count)
    assert(original.isEmpty || scaled.count == original.count)
    assert(zone == .glyph || original.isEmpty)  // really should be all zeros, but why waste the effort

    let hinted = hinted.isEmpty ? scaled : hinted
    let original: [UnscaledCoord] = original.isEmpty ? scaled.map { _ in .zero } : original
    let points = (0..<scaled.count).map { idx in
      OutlinePoint(original: original[idx], scaled: scaled[idx], hinted: hinted[idx])
    }
    setPoints(points, forZone: zone)
  }

  mutating func setPoints(_ points: [OutlinePoint], forZone zone: ZoneType) {
    interface.setPoints(points, forZone: zone)
    interface.setContours([0..<points.count], forZone: zone)
  }

  mutating func setContours(_ contours: [Range<Int>], forZone zoneType: ZoneType) {
    interface.setContours(contours, forZone: zoneType)
  }

  mutating func setStorageValue(_ value: Int32, at: UInt, sourceLocation: SourceLocation = #_sourceLocation) {
    interface.setStorageValue(value, at: at, sourceLocation: sourceLocation)
  }

  mutating func setVariationCoord(_ coord: [F2Dot14]) {
    interface.setVariationCoord(coord.map(\.bitPattern))
  }

  mutating func setNullVariationCoord(count: Int) {
    interface.setNullVariationCoord(count: count)
  }

  mutating func setScaleFactors(
    xStretch: F16Dot16 = 512,
    yStretch: F16Dot16 = 512,
    unitsPerEm: Int16 = 2_048,
    pointSize: Int32 = 12,
    cvtScale: F16Dot16 = 512,
    isRotated: Bool = false,
    isStretched: Bool = false
  ) {
    hasSetScaleFactors = true
    interface.setScaleFactors(
      xStretch: xStretch,
      yStretch: yStretch,
      unitsPerEm: unitsPerEm,
      pointSize: pointSize,
      cvtScale: cvtScale,
      isRotated: isRotated,
      isStretched: isStretched
    )
  }

  func effectiveCVTScale() -> F16Dot16 {
    interface.effectiveCVTScale()
  }

  mutating func validate(
    except exceptions: StateComponentOptions = [],
    sourceLocation: SourceLocation = #_sourceLocation
  ) {
    didValidate = true

    let expected = expectedEngineState ?? engineState()
    let actual = interface.engineState()
    if !exceptions.contains(.cvt) {
      if expected.cvt.count != actual.cvt.count {
        Issue.record(
          "validation error: cvt count mismatch. expected \(expected.cvt.count), found \(actual.cvt.count)",
          sourceLocation: sourceLocation
        )
      }

      for idx in 0..<expected.cvt.count where expected.cvt[idx] != actual.cvt[idx] {
        Issue.record(
          "validation error: cvt element mismatch at index \(idx). expected \(expected.cvt[idx]), found \(actual.cvt[idx])",
          sourceLocation: sourceLocation
        )
      }
    }

    if !exceptions.contains(.stack) {
      if expected.stack.count != actual.stack.count {
        let showStack = expected.stack.count < 100 && actual.stack.count < 100
        let expectedDetail = showStack ? "(\(expected.stack))" : ""
        let actualDetail = showStack ? "(\(actual.stack))" : ""
        Issue.record(
     """
     validation error: stack count mismatch. \
     expected \(expected.stack.count) \(expectedDetail), \
     found \(actual.stack.count) \(actualDetail)
     """,
     sourceLocation: sourceLocation
        )
      }

      for idx in 0..<expected.stack.count where expected.stack[idx] != actual.stack[idx] {
        Issue.record(
     """
     validation error: stack element mismatch at index \(idx). \
     expected \(expected.stack[idx]), found \(actual.stack[idx])
     """,
     sourceLocation: sourceLocation
        )
      }
    }

    if !exceptions.contains(.storage) {
      if expected.storage.count != actual.storage.count {
        Issue.record(
          "validation error: storage count mismatch. expected \(expected.storage.count), found \(actual.storage.count)",
          sourceLocation: sourceLocation
        )
      }

      for idx in 0..<expected.storage.count where expected.storage[idx] != actual.storage[idx] {
        Issue.record(
     """
     validation error: storage element mismatch at index \(idx). \
     expected \(expected.storage[idx]), found \(actual.storage[idx])
     """,
     sourceLocation: sourceLocation
        )
      }
    }

    if !exceptions.contains(.glyphPoints) {
      validate(pointZone: actual.glyphPoints, against: expected.glyphPoints, sourceLocation: sourceLocation)
    }

    if !exceptions.contains(.twilightPoints) {
      validate(pointZone: actual.twilightPoints, against: expected.twilightPoints, sourceLocation: sourceLocation)
    }

    if !exceptions.contains(.autoFlip), actual.variables.autoFlip != expected.variables.autoFlip {
      Issue.record(
        "validation error: autoFlip mismatch. expected \(expected.variables.autoFlip), found \(actual.variables.autoFlip)",
        sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.controlValueCutIn),
       actual.variables.controlValueCutIn != expected.variables.controlValueCutIn {
      Issue.record(
    """
    validation error: controlValueCutIn mismatch. \
    expected \(expected.variables.controlValueCutIn), \
    found \(actual.variables.controlValueCutIn)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.deltaBase), actual.variables.deltaBase != expected.variables.deltaBase {
      Issue.record(
    """
    validation error: deltaBase mismatch. \
    expected \(expected.variables.deltaBase), found \(actual.variables.deltaBase)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.deltaShift), actual.variables.deltaShift != expected.variables.deltaShift {
      Issue.record(
    """
    validation error: deltaShift mismatch. \
    expected \(expected.variables.deltaShift), found \(actual.variables.deltaShift)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.dualProjectionVector),
       actual.variables.dualProjectionVector != expected.variables.dualProjectionVector {
      let expectedDesc = String(describing: expected.variables.dualProjectionVector)
      let actualDesc = String(describing: actual.variables.dualProjectionVector)
      Issue.record(
    """
    validation error: dualProjectionVector mismatch. \
    expected \(expectedDesc), found \(actualDesc)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.freedomVector), actual.variables.freedomVector != expected.variables.freedomVector {
      Issue.record(
    """
    validation error: freedomVector mismatch. \
    expected \(expected.variables.freedomVector), found \(actual.variables.freedomVector)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.instructControl),
       actual.variables.instructControl != expected.variables.instructControl {
      Issue.record(
    """
    validation error: instructControl mismatch. \
    expected \(expected.variables.instructControl), \
    found \(actual.variables.instructControl)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.loop), actual.variables.loop != expected.variables.loop {
      Issue.record(
        "validation error: loop mismatch. expected \(expected.variables.loop), found \(actual.variables.loop)",
        sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.minimumDistance),
       actual.variables.minimumDistance != expected.variables.minimumDistance {
      Issue.record(
    """
    validation error: minimumDistance mismatch. \
    expected \(expected.variables.minimumDistance), \
    found \(actual.variables.minimumDistance)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.projectionVector),
       actual.variables.projectionVector != expected.variables.projectionVector {
      Issue.record(
    """
    validation error: projectionVector mismatch. \
    expected \(expected.variables.projectionVector), \
    found \(actual.variables.projectionVector)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.roundState), actual.variables.roundState != expected.variables.roundState {
      Issue.record(
    """
    validation error: roundState mismatch. \
    expected \(expected.variables.roundState), found \(actual.variables.roundState)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.referencePoints), actual.variables.rp0 != expected.variables.rp0 {
      Issue.record(
        "validation error: rp0 mismatch. expected \(expected.variables.rp0), found \(actual.variables.rp0)",
        sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.referencePoints), actual.variables.rp1 != expected.variables.rp1 {
      Issue.record(
        "validation error: rp1 mismatch. expected \(expected.variables.rp1), found \(actual.variables.rp1)",
        sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.referencePoints), actual.variables.rp2 != expected.variables.rp2 {
      Issue.record(
        "validation error: rp2 mismatch. expected \(expected.variables.rp2), found \(actual.variables.rp2)",
        sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.scanControl), actual.variables.scanControl != expected.variables.scanControl {
      Issue.record(
    """
    validation error: scanControl mismatch. \
    expected \(expected.variables.scanControl), found \(actual.variables.scanControl)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.singleWidthCutIn),
       actual.variables.singleWidthCutIn != expected.variables.singleWidthCutIn {
      Issue.record(
    """
    validation error: singleWidthCutIn mismatch. \
    expected \(expected.variables.singleWidthCutIn), \
    found \(actual.variables.singleWidthCutIn)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.singleWidthValue),
       actual.variables.singleWidthValue != expected.variables.singleWidthValue {
      Issue.record(
    """
    validation error: singleWidthValue mismatch. \
    expected \(expected.variables.singleWidthValue), \
    found \(actual.variables.singleWidthValue)
    """,
    sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.zonePointers), actual.variables.zp0 != expected.variables.zp0 {
      Issue.record(
        "validation error: zp0 mismatch. expected \(expected.variables.zp0), found \(actual.variables.zp0)",
        sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.zonePointers), actual.variables.zp1 != expected.variables.zp1 {
      Issue.record(
        "validation error: zp1 mismatch. expected \(expected.variables.zp1), found \(actual.variables.zp1)",
        sourceLocation: sourceLocation
      )
    }

    if !exceptions.contains(.zonePointers), actual.variables.zp2 != expected.variables.zp2 {
      Issue.record(
        "validation error: zp2 mismatch. expected \(expected.variables.zp2), found \(actual.variables.zp2)",
        sourceLocation: sourceLocation
      )
    }
  }

  private func validate(
    pointZone actual: EngineStatePointZone,
    against expected: EngineStatePointZone,
    sourceLocation: SourceLocation
  ) {
    precondition(expected.zoneType == actual.zoneType)
    guard expected.count == actual.count else {
      Issue.record(
        "validation error: \(actual.zoneType) zone point count mismatch. expected \(expected.count), found \(actual.count)",
        sourceLocation: sourceLocation
      )
      return
    }

    for idx in 0..<expected.count where expected.points[idx] != actual.points[idx] {
      Issue.record(
    """
    validation error: \(actual.zoneType) point mismatch at index \(idx). \
    expected \(expected.points[idx].debugDescription), \
    found \(actual.points[idx].debugDescription)
    """,
    sourceLocation: sourceLocation
      )
    }
  }
}

// MARK: Shared Helpers

func phantomPoints(forOutlinePoints allPoints: [OutlinePoint]) -> [OutlinePoint] {
  guard !allPoints.isEmpty else {
    return .init(repeating: .zero, count: 8)  // privatePhantomCount
  }

  // make up non-unreasonable values
  var minPoint = OutlinePoint(
    original: .init(x: .max, y: .max),
    scaled: .init(x: .max, y: .max),
    hinted: .init(x: .max, y: .max)
  )
  var maxPoint = OutlinePoint(
    original: .init(x: .min, y: .min),
    scaled: .init(x: .min, y: .min),
    hinted: .init(x: .min, y: .min)
  )
  for point in allPoints {
    minPoint.original.x = min(minPoint.original.x, point.original.x)
    minPoint.original.y = min(minPoint.original.y, point.original.y)
    minPoint.scaled.x = min(minPoint.scaled.x, point.scaled.x)
    minPoint.scaled.y = min(minPoint.scaled.y, point.scaled.y)
    minPoint.hinted.x = min(minPoint.hinted.x, point.hinted.x)
    minPoint.hinted.y = min(minPoint.hinted.y, point.hinted.y)

    maxPoint.original.x = max(maxPoint.original.x, point.original.x)
    maxPoint.original.y = max(maxPoint.original.y, point.original.y)
    maxPoint.scaled.x = max(maxPoint.scaled.x, point.scaled.x)
    maxPoint.scaled.y = max(maxPoint.scaled.y, point.scaled.y)
    maxPoint.hinted.x = max(maxPoint.hinted.x, point.hinted.x)
    maxPoint.hinted.y = max(maxPoint.hinted.y, point.hinted.y)
  }
  // use the same points for public and private phantoms, which is wrong, but if you care, you need to
  // bring your own because this method doesn't have enough context to recreate them.
  let left = OutlinePoint(
    original: .init(
      x: minPoint.original.x,
      y: smallIntAverage(minPoint.original.y, maxPoint.original.y)
    ),
    scaled: .init(
      x: minPoint.scaled.x,
      y: .init(bitPattern: smallIntAverage(minPoint.scaled.y.bitPattern, maxPoint.scaled.y.bitPattern))
    ),
    hinted: .init(
      x: minPoint.hinted.x,
      y: .init(bitPattern: smallIntAverage(minPoint.hinted.y.bitPattern, maxPoint.hinted.y.bitPattern))
    )
  )

  let right = OutlinePoint(
    original: .init(
      x: maxPoint.original.x,
      y: smallIntAverage(minPoint.original.y, maxPoint.original.y)
    ),
    scaled: .init(
      x: maxPoint.scaled.x,
      y: .init(bitPattern: smallIntAverage(minPoint.scaled.y.bitPattern, maxPoint.scaled.y.bitPattern))
    ),
    hinted: .init(
      x: maxPoint.hinted.x,
      y: .init(bitPattern: smallIntAverage(minPoint.hinted.y.bitPattern, maxPoint.hinted.y.bitPattern))
    )
  )

  let top = OutlinePoint(
    original: .init(
      x: smallIntAverage(minPoint.original.x, maxPoint.original.x),
      y: maxPoint.original.y
    ),
    scaled: .init(
      x: .init(bitPattern: smallIntAverage(minPoint.scaled.x.bitPattern, maxPoint.scaled.x.bitPattern)),
      y: maxPoint.scaled.y
    ),
    hinted: .init(
      x: .init(bitPattern: smallIntAverage(minPoint.hinted.x.bitPattern, maxPoint.hinted.x.bitPattern)),
      y: maxPoint.hinted.y
    )
  )

  let bottom = OutlinePoint(
    original: .init(
      x: smallIntAverage(minPoint.original.x, maxPoint.original.x),
      y: minPoint.original.y
    ),
    scaled: .init(
      x: .init(bitPattern: smallIntAverage(minPoint.scaled.x.bitPattern, maxPoint.scaled.x.bitPattern)),
      y: minPoint.scaled.y
    ),
    hinted: .init(
      x: .init(bitPattern: smallIntAverage(minPoint.hinted.x.bitPattern, maxPoint.hinted.x.bitPattern)),
      y: minPoint.hinted.y
    )
  )
  return [left, right, top, bottom, left, right, top, bottom]
}

private func smallIntAverage<T: FixedWidthInteger>(_ a: T, _ b: T) -> T {
  assert(T.bitWidth <= 32)  // Int64 is supposed to be a promotion here
  return T((Int64(a) + Int64(b)) / 2)
}
