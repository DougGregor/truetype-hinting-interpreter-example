import SwiftTrueTypeInterpreter
import Testing

typealias F58Dot6 = SwiftTrueTypeInterpreter.F58Dot6

@Suite("Coverage Tests")
struct CoverageTests {
  // MARK: - FixedPoint description (CustomStringConvertible)

  @Test func fixedPointDescription() {
    let value = F26Dot6(1.5)
    let desc = value.description
    #expect(desc.contains("1"))
    #expect(!desc.isEmpty)
  }

  @Test func fixedPointDescriptionNegative() {
    let value = F26Dot6(-2.25)
    let desc = value.description
    #expect(desc.hasPrefix("-"))
  }

  @Test func fixedPointDescriptionZero() {
    let value = F26Dot6(0)
    #expect(!value.description.isEmpty)
  }

  // MARK: - FixedPoint init?(String) (LosslessStringConvertible)

  @Test func fixedPointInitFromString() {
    let value = F26Dot6(1.5)
    let desc = value.description
    let roundTripped = F26Dot6(desc)
    #expect(roundTripped != nil)
  }

  @Test func fixedPointInitFromInvalidString() {
    let value = F26Dot6("not a number")
    #expect(value == nil)
  }

  @Test func fixedPointInitFromEmptyString() {
    let value = F26Dot6("")
    #expect(value == nil)
  }

  // MARK: - FixedPoint init?(exactly: BinaryInteger)

  @Test func fixedPointInitExactlyRepresentable() {
    let value = F26Dot6(exactly: 10 as Int)
    #expect(value != nil)
    #expect(value == F26Dot6(10))
  }

  @Test func fixedPointInitExactlyOverflow() {
    // Int64.max should overflow F26Dot6 (which has Int32 storage)
    let value = F26Dot6(exactly: Int64.max)
    #expect(value == nil)
  }

  @Test func fixedPointInitExactlyZero() {
    let value = F26Dot6(exactly: 0 as Int)
    #expect(value != nil)
    #expect(value == F26Dot6(0))
  }

  // MARK: - FixedPoint.magnitude

  @Test func fixedPointMagnitudePositive() {
    let value = F26Dot6(3.5)
    let mag = value.magnitude
    #expect(mag.bitPattern == value.bitPattern.magnitude)
  }

  @Test func fixedPointMagnitudeNegative() {
    let value = F26Dot6(-3.5)
    let mag = value.magnitude
    #expect(mag.bitPattern == value.bitPattern.magnitude)
  }

  @Test func fixedPointMagnitudeZero() {
    let value = F26Dot6(0)
    let mag = value.magnitude
    #expect(mag.bitPattern == 0)
  }

  // MARK: - FixedPoint.name

  @Test func fixedPointName() {
    #expect(F26Dot6.name.contains("26"))
    #expect(F26Dot6.name.contains("6"))
    #expect(F2Dot14.name.contains("2"))
    #expect(F2Dot14.name.contains("14"))
  }

  // MARK: - defaultRounding on F58Dot6 and F2Dot30

  @Test func f58Dot6DefaultRounding() {
    #expect(F58Dot6.defaultRounding == .toNearestOrAway)
  }

  @Test func f2Dot30DefaultRounding() {
    #expect(F2Dot30.defaultRounding == .toNearestOrAway)
  }

  // MARK: - FixedPointMagnitude properties

  @Test func magnitudeTypeFractionBits() {
    let mag = F26Dot6(1.0).magnitude
    #expect(type(of: mag).fractionBits == F26Dot6.fractionBits)
  }

  @Test func magnitudeTypeDefaultRounding() {
    let mag = F26Dot6(1.0).magnitude
    #expect(type(of: mag).defaultRounding == F26Dot6.defaultRounding)
  }

  // MARK: - Interpreter.setCVT

  @Test func setCVTFromSpan() {
    let maxp = sfntMaxProfileTable(version: F16Dot16(1.0).bitPattern)
    let interp = SwiftTrueTypeInterpreter(maxp: maxp, cvtCount: 4)
    let values: [Int32] = [100, 200, 300, 400]
    interp.setCVT(values.span)
  }

  // MARK: - dividedIfRepresentable with various rounding modes

  @Test func fixedPointDivisionNearestOrEven() {
    // Exercise the toNearestOrEven path in the FixedWidthInteger dividing() method.
    // 2/3 produces a remainder > half of the divisor, triggering the nextUp branch.
    let a = F26Dot6(2)
    let b = F26Dot6(3)
    let result = a.dividedIfRepresentable(by: b, rounding: .toNearestOrEven)
    #expect(result != nil)
  }

  // MARK: - Unsigned FixedPoint magnitude (self-returning)

  @Test func unsignedFixedPointMagnitude() {
    // FixedPointMagnitude (unsigned) has magnitude == self
    let value = F26Dot6(5)
    let mag = value.magnitude  // FixedPointMagnitude<F26Dot6>
    let magMag = mag.magnitude  // exercises the unsigned magnitude getter
    #expect(mag.bitPattern == magMag.bitPattern)
  }

  // MARK: - Stack growth via large NPUSHB

  @Test func stackGrowthViaLargeNPUSHB() throws {
    // Stack starts with capacity 1024. NPUSHB with 255 bytes won't overflow it,
    // but doing it 5 times (1275 total pushes) will force _grow(by:).
    // Build a program: 5x(NPUSHB 255 <255 bytes>) then 1275x POP
    let maxp = sfntMaxProfileTable(version: F16Dot16(1.0).bitPattern)
    let interp = SwiftTrueTypeInterpreter(maxp: maxp, cvtCount: 0)

    var program: [UInt8] = []
    for _ in 0..<5 {
      program.append(0x40)  // NPUSHB
      program.append(255)  // count
      program.append(contentsOf: [UInt8](repeating: 1, count: 255))
    }
    // Pop everything to leave stack clean
    program.append(contentsOf: [UInt8](repeating: 0x21, count: 1_275))  // POP

    var parBlock = fnt_ParameterBlock()
    try interp.runProgram(
      fpgm: program.span,
      prep: Span<UInt8>(),
      glyf: Span<UInt8>(),
      unscaledOutlineIsWrong: false,
      parBlock: &parBlock
    )
  }

  @Test func fixedPointDivisionToOdd() {
    let a = F26Dot6(1)
    let b = F26Dot6(3)
    let result = a.dividedIfRepresentable(by: b, rounding: .toOdd)
    #expect(result != nil)
  }

  @Test func fixedPointDivisionRequireExact() {
    // 1/3 is not exact, should return nil
    let a = F26Dot6(1)
    let b = F26Dot6(3)
    let result = a.dividedIfRepresentable(by: b, rounding: .requireExact)
    #expect(result == nil)

    // 1/1 is exact, should succeed
    let c = F26Dot6(1)
    let d = F26Dot6(1)
    let exact = c.dividedIfRepresentable(by: d, rounding: .requireExact)
    #expect(exact == F26Dot6(1))
  }

  @Test func fixedPointDivisionStochastic() {
    let a = F26Dot6(1)
    let b = F26Dot6(3)
    let result = a.dividedIfRepresentable(by: b, rounding: .stochastically)
    #expect(result != nil)
  }

  // MARK: - FixedVector.magnitude(rounding:) saturation on overflow

  @Test func fixedVectorMagnitudeSaturatesOnOverflow() {
    // Construct a vector whose Pythagorean magnitude exceeds F26Dot6.max so the
    // `init(ifRepresentable:)` lookup fails and the `?? .max` fallback fires.
    let huge = F26Dot6.max
    let v = SwiftTrueTypeInterpreter.FixedVector<F26Dot6>(x: huge, y: huge)
    let m = v.magnitude()
    #expect(m == .max)
  }
}
