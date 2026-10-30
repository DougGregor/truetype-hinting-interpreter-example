// Stub types modeling the C structures consumed by the interpreter, for standalone compilation.

/// Maximum profile table from the TrueType `maxp` table.
public struct sfntMaxProfileTable: Sendable {
  public var version: Int32
  public var numGlyphs: UInt16
  public var maxPoints: UInt16
  public var maxContours: UInt16
  public var maxCompositePoints: UInt16
  public var maxCompositeContours: UInt16
  public var maxElements: UInt16
  public var maxTwilightPoints: UInt16
  public var maxStorage: UInt16
  public var maxFunctionDefs: UInt16
  public var maxInstructionDefs: UInt16
  public var maxStackElements: UInt16
  public var maxSizeOfInstructions: UInt16
  public var maxComponentElements: UInt16
  public var maxComponentDepth: UInt16

  public init(
    version: Int32 = 0x0001_0000,  // 1.0 in F16Dot16
    numGlyphs: UInt16 = 0,
    maxPoints: UInt16 = 0,
    maxContours: UInt16 = 1,
    maxCompositePoints: UInt16 = 0,
    maxCompositeContours: UInt16 = 0,
    maxElements: UInt16 = 2,  // "set to 2, or 1 if no twilightzone points"
    maxTwilightPoints: UInt16 = 0,
    maxStorage: UInt16 = 1_024,
    maxFunctionDefs: UInt16 = 1,
    maxInstructionDefs: UInt16 = 0,
    maxStackElements: UInt16 = 1_024,
    maxSizeOfInstructions: UInt16 = 0,
    maxComponentElements: UInt16 = 0,
    maxComponentDepth: UInt16 = 0
  ) {
    self.version = version
    self.numGlyphs = numGlyphs
    self.maxPoints = maxPoints
    self.maxContours = maxContours
    self.maxCompositePoints = maxCompositePoints
    self.maxCompositeContours = maxCompositeContours
    self.maxElements = maxElements
    self.maxTwilightPoints = maxTwilightPoints
    self.maxStorage = maxStorage
    self.maxFunctionDefs = maxFunctionDefs
    self.maxInstructionDefs = maxInstructionDefs
    self.maxStackElements = maxStackElements
    self.maxSizeOfInstructions = maxSizeOfInstructions
    self.maxComponentElements = maxComponentElements
    self.maxComponentDepth = maxComponentDepth
  }
}

/// Element type representing a zone's outline data.
///
/// The point arrays are parallel; each must hold at least `maxPointCount` elements, and the
/// contour arrays (`sp`, `ep`) at least `maxContourCount` elements. The interpreter checks
/// these requirements when it wraps an element in a zone. The arrays are uniquely owned, so an
/// element can't be copied and the interpreter's access to it never triggers a copy.
public struct fnt_ElementType: ~Copyable {
  public var contourCount: Int32 = 0
  public var pointCount: Int32 = 0
  public var x: UniqueArray<Int32> = .init()  // Scaled hinted points
  public var y: UniqueArray<Int32> = .init()  // Scaled hinted points
  public var sp: UniqueArray<UInt16> = .init()  // Start points
  public var ep: UniqueArray<UInt16> = .init()  // End points
  public var onCurve: UniqueArray<UInt8> = .init()  // On/off curve flags
  public var f: UniqueArray<UInt8> = .init()  // Internal flags
  public var ox: UniqueArray<Int32> = .init()  // Scaled unhinted points
  public var oy: UniqueArray<Int32> = .init()  // Scaled unhinted points
  public var oox: UniqueArray<Int16> = .init()  // Unscaled unhinted points
  public var ooy: UniqueArray<Int16> = .init()  // Unscaled unhinted points
  public var glyphIndex: Int32 = 0
  public var maxContourCount: Int32 = 0
  public var maxPointCount: Int32 = 0

  public init() {}
}

/// Parameter block for communicating interpreter state with the rasterizer.
public struct fnt_ParameterBlock {
  public var wTCI: Int32 = 0  // Width table cut in
  public var sWCI: Int32 = 0  // Single width cut in
  public var scaledSW: Int32 = 0  // Scaled single width
  public var scanControl: Int32 = 0
  public var instructControl: Int32 = 0
  public var minimumDistance: Int32 = 0
  public var periodMask: Int32 = 0
  public var period45: Int32 = 0
  public var period: Int16 = 0
  public var phase: Int16 = 0
  public var threshold: Int16 = 0
  public var deltaBase: Int16 = 0
  public var deltaShift: Int16 = 0
  public var sW: Int16 = 0  // Single width in font units
  public var autoFlip: Int8 = 0
  public var composedSRoundValue: UInt8 = 0

  public init() {}
}

/// Phantom point counts from the TrueType specification.
struct PhantomPointCount: Sendable {
  let rawValue: Int32
}

/// Number of public phantom points (LSB, RSB, TSB, BSB).
let kPublicPhantomCount = PhantomPointCount(rawValue: 4)

/// Total number of phantom points including private edge phantoms.
let kPrivatePhantomCount = PhantomPointCount(rawValue: 8)
