import SwiftTrueTypeInterpreter

enum HintingInstruction {
  case SVTCA_Y    // 0x00. aka SVTCA0
  case SVTCA_X    // 0x01. aka SVTCA1
  case SPVTCA_Y   // 0x02
  case SPVTCA_X   // 0x03
  case SFVTCA_Y   // 0x04
  case SFVTCA_X   // 0x05
  case SPVTL_0    // 0x06
  case SPVTL_1    // 0x07
  case SFVTL_0    // 0x08
  case SFVTL_1    // 0x09
  case SPVFS      // 0x0A
  case SFVFS      // 0x0B
  case GPV        // 0x0C
  case GFV        // 0x0D
  case SFVTPV     // 0x0E
  case ISECT      // 0x0F
  case SRP0       // 0x10
  case SRP1       // 0x11
  case SRP2       // 0x12
  case SZP0       // 0x13
  case SZP1       // 0x14
  case SZP2       // 0x15
  case SZPS       // 0x16
  case SLOOP      // 0x17
  case RTG        // 0x18
  case RTHG       // 0x19
  case SMD        // 0x1A
  case ELSE       // 0x1B
  case JMPR       // 0x1C
  case SCVTCI     // 0x1D
  case SSWCI      // 0x1E
  case SSW        // 0x1F
  case DUP        // 0x20
  case POP        // 0x21
  case CLEAR      // 0x22
  case SWAP       // 0x23
  case DEPTH      // 0x24
  case CINDEX     // 0x25
  case MINDEX     // 0x26
  case ALIGNPTS   // 0x27
  case UTP        // 0x29
  case LOOPCALL   // 0x2A
  case CALL       // 0x2B
  case FDEF       // 0x2C
  case ENDF       // 0x2D
  case MDAP_0		// 0x2E
  case MDAP_1		// 0x2F
  case IUP_Y		// 0x30
  case IUP_X		// 0x31
  case SHP_0		// 0x32
  case SHP_1		// 0x33
  case SHC_0		// 0x34
  case SHC_1		// 0x35
  case SHZ_0		// 0x36
  case SHZ_1		// 0x37
  case SHPIX      // 0x38
  case IP         // 0x39
  case MSIRP(setRP0: Bool) // 0x3A-0x3B
  case ALIGNRP    // 0x3C
  case RTDG       // 0x3D
  case MIAP_0		// 0x3E
  case MIAP_1		// 0x3F
  case NPUSHB([UInt8], n: UInt8? = nil) // 0x40, 'n' for clarity, preference, or deliberate mismatches
  case NPUSHW([Int16], n: UInt8? = nil) // 0x41, 'n' for clarity, preference, or deliberate mismatches
  case WS         // 0x42
  case RS         // 0x43
  case WCVTP      // 0x44
  case RCVT       // 0x45
  case GC_0       // 0x46
  case GC_1       // 0x47
  case SCFS       // 0x48
  case MD_1       // 0x49
  case MD_0       // 0x4A
  case MPPEM      // 0x4B
  case MPS        // 0x4C
  case FLIPON     // 0x4D
  case FLIPOFF    // 0x4E
  case DEBUG      // 0x4F
  case LT         // 0x50
  case LTEQ       // 0x51
  case GT         // 0x52
  case GTEQ       // 0x53
  case EQ         // 0x54
  case NEQ        // 0x55
  case ODD        // 0x56
  case EVEN       // 0x57
  case IF         // 0x58
  case EIF        // 0x59
  case AND        // 0x5A
  case OR         // 0x5B
  case NOT        // 0x5C
  case DELTAP1    // 0x5D
  case SDB        // 0x5E
  case SDS        // 0x5F
  case ADD        // 0x60
  case SUB        // 0x61
  case DIV        // 0x62
  case MUL        // 0x63
  case ABS        // 0x64
  case NEG        // 0x65
  case FLOOR      // 0x66
  case CEILING    // 0x67
  case ROUND_0	// 0x68
  case ROUND_1	// 0x69
  case ROUND_2	// 0x6a
  case ROUND_3	// 0x6b
  case NROUND_0	// 0x6c
  case NROUND_1	// 0x6d
  case NROUND_2	// 0x6e
  case NROUND_3	// 0x6f
  case WCVTF      // 0x70
  case DELTAP2    // 0x71
  case DELTAP3    // 0x72
  case DELTAC1    // 0x73
  case DELTAC2    // 0x74
  case DELTAC3    // 0x75
  case SROUND     // 0x76
  case S45ROUND   // 0x77
  case JROT       // 0x78
  case JROF       // 0x79
  case ROFF       // 0x7A
  case RUTG       // 0x7C
  case RDTG       // 0x7D
  case SANGW      // 0x7E
  case AA         // 0x7F
  case FLIPPT     // 0x80
  case FLIPRGON   // 0x81
  case FLIPRGOFF  // 0x82
  case SCANCTRL   // 0x85
  case SDPVTL_0   // 0x86
  case SDPVTL_1   // 0x87
  case GETINFO    // 0x88
  case IDEF       // 0x89
  case ROLL       // 0x8A
  case MAX        // 0x8B
  case MIN        // 0x8C
  case SCANTYPE   // 0x8D
  case INSTCTRL   // 0x8E
  case GETVARIATION	// 0x91
  case GETDATA	// 0x92
  case PUSHB([UInt8], n: UInt8? = nil)	// 0xB0-B7, 'n' for clarity, preference or deliberate mismatches
  case PUSHW([Int16], n: UInt8? = nil)	// 0xB8-BF, 'n' for clarity, preference or deliberate mismatches
  case MDRP(distanceType: UInt8, roundDistance: Bool, useMinimumDistance: Bool, resetRP0: Bool) // 0xC0...0xDF
  case MIRP(distanceType: UInt8, roundDistance: Bool, useMinimumDistance: Bool, resetRP0: Bool) // 0xE0...0xFF

  // MARK: Test conveniences
  case setPV(FixedVector<F2Dot14>)
  case setFV(FixedVector<F2Dot14>)
  case setSingleWidthValue(F26Dot6)

  /// Sets point in zone, within limits. Note this will overwrite graphicsState.zp2,
  /// the freedom vector, and the projection vector
  case setPoint(OutlineCoord, at: Int, in: SwiftTrueTypeInterpreter.Zone.ZoneType)
  case setRoundState(RoundState)
  case pushF26Dot6(F26Dot6)
  case pushInt32(Int32)

  /// can be used to insert undefined opcodes into the stream, helpful for idef testing
  case literal(UInt8)

  static func MDRP(roundDistance: Bool, useMinimumDistance: Bool, resetRP0: Bool) -> Self {
    .MDRP(distanceType: 0, roundDistance: roundDistance, useMinimumDistance: useMinimumDistance, resetRP0: resetRP0)
  }

  static func MIRP(roundDistance: Bool, useMinimumDistance: Bool, resetRP0: Bool) -> Self {
    .MIRP(distanceType: 0, roundDistance: roundDistance, useMinimumDistance: useMinimumDistance, resetRP0: resetRP0)
  }

  var opcode: UInt8 { stream[0] }

  var stream: [UInt8] {
    var stream: [UInt8] = []
    switch self {
      // TrueType hinting instructions
    case .SVTCA_Y:
      stream.append(0x00)
    case .SVTCA_X:
      stream.append(0x01)
    case .SPVTCA_Y:
      stream.append(0x02)
    case .SPVTCA_X:
      stream.append(0x03)
    case .SFVTCA_Y:
      stream.append(0x04)
    case .SFVTCA_X:
      stream.append(0x05)
    case .SPVTL_0:
      stream.append(0x06)
    case .SPVTL_1:
      stream.append(0x07)
    case .SFVTL_0:
      stream.append(0x08)
    case .SFVTL_1:
      stream.append(0x09)
    case .SPVFS:
      stream.append(0x0A)
    case .SFVFS:
      stream.append(0x0B)
    case .GPV:
      stream.append(0x0C)
    case .GFV:
      stream.append(0x0D)
    case .SFVTPV:
      stream.append(0x0E)
    case .ISECT:
      stream.append(0x0F)
    case .SRP0:
      stream.append(0x10)
    case .SRP1:
      stream.append(0x11)
    case .SRP2:
      stream.append(0x12)
    case .SZP0:
      stream.append(0x13)
    case .SZP1:
      stream.append(0x14)
    case .SZP2:
      stream.append(0x15)
    case .SZPS:
      stream.append(0x16)
    case .SLOOP:
      stream.append(0x17)
    case .RTG:
      stream.append(0x18)
    case .RTHG:
      stream.append(0x19)
    case .SMD:
      stream.append(0x1A)
    case .ELSE:
      stream.append(0x1B)
    case .JMPR:
      stream.append(0x1C)
    case .SCVTCI:
      stream.append(0x1D)
    case .SSWCI:
      stream.append(0x1E)
    case .SSW:
      stream.append(0x1F)
    case .DUP:
      stream.append(0x20)
    case .POP:
      stream.append(0x21)
    case .CLEAR:
      stream.append(0x22)
    case .SWAP:
      stream.append(0x23)
    case .DEPTH:
      stream.append(0x24)
    case .CINDEX:
      stream.append(0x25)
    case .MINDEX:
      stream.append(0x26)
    case .ALIGNPTS:
      stream.append(0x27)
    case .UTP:
      stream.append(0x29)
    case .LOOPCALL:
      stream.append(0x2A)
    case .CALL:
      stream.append(0x2B)
    case .FDEF:
      stream.append(0x2C)
    case .ENDF:
      stream.append(0x2D)
    case .MDAP_0:
      stream.append(0x2E)
    case .MDAP_1:
      stream.append(0x2F)
    case .IUP_Y:
      stream.append(0x30)
    case .IUP_X:
      stream.append(0x31)
    case .SHP_0:
      stream.append(0x32)
    case .SHP_1:
      stream.append(0x33)
    case .SHC_0:
      stream.append(0x34)
    case .SHC_1:
      stream.append(0x35)
    case .SHZ_0:
      stream.append(0x36)
    case .SHZ_1:
      stream.append(0x37)
    case .SHPIX:
      stream.append(0x38)
    case .IP:
      stream.append(0x39)
    case .MSIRP(let setRP0):
      stream.append(setRP0 ? 0x3B : 0x3A)
    case .ALIGNRP:
      stream.append(0x3C)
    case .RTDG:
      stream.append(0x3D)
    case .MIAP_0:
      stream.append(0x3E)
    case .MIAP_1:
      stream.append(0x3F)
    case let .NPUSHB(bytes, count):
      stream.append(0x40)
      if let count {
        stream.append(count)
      } else {
        stream.append(UInt8(bytes.count))
      }
      stream.append(contentsOf: bytes)
    case let .NPUSHW(words, count):
      stream.append(0x41)
      if let count {
        stream.append(count)
      } else {
        stream.append(UInt8(words.count))
      }
      // words are big-endian in the stream
      words.forEach { stream.append(contentsOf: [UInt8(bitPattern: Int8($0 >> 8)), UInt8($0 & 0xFF)]) }
    case .WS:
      stream.append(0x42)
    case .RS:
      stream.append(0x43)
    case .WCVTP:
      stream.append(0x44)
    case .RCVT:
      stream.append(0x45)
    case .GC_0:
      stream.append(0x46)
    case .GC_1:
      stream.append(0x47)
    case .SCFS:
      stream.append(0x48)
    case .MD_1:
      stream.append(0x49)
    case .MD_0:
      stream.append(0x4A)
    case .MPPEM:
      stream.append(0x4B)
    case .MPS:
      stream.append(0x4C)
    case .FLIPON:
      stream.append(0x4D)
    case .FLIPOFF:
      stream.append(0x4E)
    case .DEBUG:
      stream.append(0x4F)
    case .LT:
      stream.append(0x50)
    case .LTEQ:
      stream.append(0x51)
    case .GT:
      stream.append(0x52)
    case .GTEQ:
      stream.append(0x53)
    case .EQ:
      stream.append(0x54)
    case .NEQ:
      stream.append(0x55)
    case .ODD:
      stream.append(0x56)
    case .EVEN:
      stream.append(0x57)
    case .IF:
      stream.append(0x58)
    case .EIF:
      stream.append(0x59)
    case .AND:
      stream.append(0x5A)
    case .OR:
      stream.append(0x5B)
    case .NOT:
      stream.append(0x5C)
    case .DELTAP1:
      stream.append(0x5D)
    case .SDB:
      stream.append(0x5E)
    case .SDS:
      stream.append(0x5F)
    case .ADD:
      stream.append(0x60)
    case .SUB:
      stream.append(0x61)
    case .DIV:
      stream.append(0x62)
    case .MUL:
      stream.append(0x63)
    case .ABS:
      stream.append(0x64)
    case .NEG:
      stream.append(0x65)
    case .FLOOR:
      stream.append(0x66)
    case .CEILING:
      stream.append(0x67)
    case .ROUND_0:
      stream.append(0x68)
    case .ROUND_1:
      stream.append(0x69)
    case .ROUND_2:
      stream.append(0x6a)
    case .ROUND_3:
      stream.append(0x6b)
    case .NROUND_0:
      stream.append(0x6c)
    case .NROUND_1:
      stream.append(0x6d)
    case .NROUND_2:
      stream.append(0x6e)
    case .NROUND_3:
      stream.append(0x6f)
    case .WCVTF:
      stream.append(0x70)
    case .DELTAP2:
      stream.append(0x71)
    case .DELTAP3:
      stream.append(0x72)
    case .DELTAC1:
      stream.append(0x73)
    case .DELTAC2:
      stream.append(0x74)
    case .DELTAC3:
      stream.append(0x75)
    case .SROUND:
      stream.append(0x76)
    case .S45ROUND:
      stream.append(0x77)
    case .JROT:
      stream.append(0x78)
    case .JROF:
      stream.append(0x79)
    case .ROFF:
      stream.append(0x7A)
    case .RUTG:
      stream.append(0x7C)
    case .RDTG:
      stream.append(0x7D)
    case .SANGW:
      stream.append(0x7E)
    case .AA:
      stream.append(0x7F)
    case .FLIPPT:
      stream.append(0x80)
    case .FLIPRGON:
      stream.append(0x81)
    case .FLIPRGOFF:
      stream.append(0x82)
    case .SCANCTRL:
      stream.append(0x85)
    case .SDPVTL_0:
      stream.append(0x86)
    case .SDPVTL_1:
      stream.append(0x87)
    case .GETINFO:
      stream.append(0x88)
    case .IDEF:
      stream.append(0x89)
    case .ROLL:
      stream.append(0x8A)
    case .MAX:
      stream.append(0x8B)
    case .MIN:
      stream.append(0x8C)
    case .SCANTYPE:
      stream.append(0x8D)
    case .INSTCTRL:
      stream.append(0x8E)
    case .GETVARIATION:
      stream.append(0x91)
    case .GETDATA:
      stream.append(0x92)
    case let .PUSHB(bytes, count):
      if let count {
        stream.append(0xB0 + count - 1)
      } else {
        stream.append(0xB0 + UInt8(bytes.count) - 1)
      }
      stream.append(contentsOf: bytes)
    case let .PUSHW(words, count):
      if let count {
        stream.append(0xB8 + count - 1)
      } else {
        stream.append(0xB8 + UInt8(words.count) - 1)
      }
      // words are big-endian in the stream
      words.forEach { stream.append(contentsOf: [UInt8(bitPattern: Int8($0 >> 8)), UInt8($0 & 0xFF)]) }
    case let .MDRP(distanceType: distance, roundDistance: rd, useMinimumDistance: md, resetRP0: rrp0):
      var op: UInt8 = 0xC0
      guard 0..<4 ~= distance else {
        fatalError("distance must be 0..<4")
      }
      op += distance
      op += (rd ? 1 : 0) << 2
      op += (md ? 1 : 0) << 3
      op += (rrp0 ? 1 : 0) << 4
      stream.append(op)
    case let .MIRP(distanceType: distance, roundDistance: rd, useMinimumDistance: md, resetRP0: rrp0):
      var op: UInt8 = 0xE0
      guard 0..<4 ~= distance else {
        fatalError("distance must be 0..<4")
      }
      op += distance
      op += (rd ? 1 : 0) << 2
      op += (md ? 1 : 0) << 3
      op += (rrp0 ? 1 : 0) << 4
      stream.append(op)

      // MARK: Test conveniences
    case .setPV(let testVec):
      stream.append(contentsOf: Self.NPUSHW([testVec.x.bitPattern, testVec.y.bitPattern]).stream)
      stream.append(contentsOf: Self.SPVFS.stream)
    case .setFV(let testVec):
      stream.append(contentsOf: Self.NPUSHW([testVec.x.bitPattern, testVec.y.bitPattern]).stream)
      stream.append(contentsOf: Self.SFVFS.stream)
    case .setSingleWidthValue(let value):
      stream.append(contentsOf: Self.pushInt32(value.bitPattern).stream)
      stream.append(contentsOf: Self.SSW.stream)
    case let .setPoint(point, at: index, in: zone):
      let instructions: [Self] = [
        .PUSHB([UInt8(exactly: zone.rawValue)!]), .SZP2,
        .SVTCA_Y, .PUSHW([Int16(index)]), .pushF26Dot6(point.y), .SCFS,
        .SVTCA_X, .PUSHW([Int16(index)]), .pushF26Dot6(point.x), .SCFS,
        // reset to engine defaults
        .NPUSHB([1]), .SZPS,
      ]
      stream.append(contentsOf: instructions.flatMap(\.stream))
    case .setRoundState(let rounding):
      stream.append(contentsOf: rounding.instructions.flatMap(\.stream))
    case .pushF26Dot6(var value):
      if value == .min {
        stream.append(contentsOf: [Self.PUSHB([0]), .pushF26Dot6(.max), .SUB, .PUSHB([1]), .SUB].flatMap(\.stream))
        break
      }

      let negative = value < 0
      if negative {
        value = 0 - value
      }

      let maxSafeToPush = F26Dot6(bitPattern: 0x7FFF)
      let maxSquarable = F26Dot6(5_792.625) // bitPattern: 370728
      var pushed = F26Dot6(0)
      var instructions = [Self.PUSHW([Int16(bitPattern: UInt16(pushed.bitPattern))])]
      while pushed != value {
        let difference = value - pushed
        var change: F26Dot6
        if difference < maxSafeToPush {
          change = difference
          instructions.append(.PUSHW([Int16(bitPattern: UInt16(change.bitPattern))]))
        } else {
          change = maxSafeToPush
          instructions.append(.PUSHW([Int16(bitPattern: UInt16(change.bitPattern))]))
          while change < maxSquarable, change * change < difference {
            change *= change
            instructions.append(contentsOf: [.PUSHB([1]), .CINDEX, .MUL])
          }
        }
        instructions.append(.ADD)
        pushed += change
      }
      if negative {
        // Push 0, move the computed value above it, subtract to make negative
        instructions.append(contentsOf: [.PUSHB([0, 2]), .MINDEX, .SUB])
      }
      stream.append(contentsOf: instructions.flatMap(\.stream))
    case .pushInt32(let value):
      stream.append(contentsOf: Self.pushF26Dot6(.init(bitPattern: value)).stream)

    case .literal(let opcode):
      stream.append(opcode)
    }

    return stream
  }
}

extension RoundState {
  fileprivate var instructions: [HintingInstruction] {
    switch self {
    case .roff: return [.ROFF]
    case .rdtg: return [.RDTG]
    case .rutg: return [.RUTG]
    case .rtg:  return [.RTG]
    case .rthg: return [.RTHG]
    case .rtdg: return [.RTDG]
    default:
      switch method {
      case .mask:
        return [.NPUSHB([superParameter], n: 1), .SROUND]
      case .divide:
        return [.NPUSHB([super45Parameter], n: 1), .S45ROUND]
      }
    }
  }

  var superParameter: UInt8 {
    let garbage = F26Dot6(bitPattern: Self.garbagePeriod())
    return guessParameters(periodValues: [0.5, 1, 2, garbage])
  }

  var super45Parameter: UInt8 {
    // the last garbage value is always 0
    guessParameters(periodValues: [0x1.6a09e667f3bcdp-2, 0x1.6a09e667f3bcdp-1, 0x1.6a09e667f3bcdp+0, 0])
  }

  private func guessParameters(periodValues: [F26Dot6]) -> UInt8 {
    var phaseValues: [F26Dot6.IntegerType] = []
    phaseValues.append(0)
    phaseValues.append((period.bitPattern + 2) / 4)
    phaseValues.append((period.bitPattern + 1) / 2)
    phaseValues.append((period.bitPattern * 3 + 2) / 4)

    var thresholdValues: [F26Dot6.IntegerType] = []
    thresholdValues.append(period.bitPattern - 1)
    for i in -3..<12 {
      thresholdValues.append((F26Dot6.IntegerType(i) * period.bitPattern + 4) / 8)
    }

    let periodBits = guessIndex(value: period.bitPattern, from: periodValues.map(\.bitPattern))
    let phaseBits = guessIndex(value: phase.bitPattern, from: phaseValues)
    let thresholdBits = guessIndex(value: threshold.bitPattern, from: thresholdValues)
    return UInt8(periodBits << 6 | phaseBits << 4 | thresholdBits)
  }
}

private func guessIndex<T: Strideable>(value: T, from set: [T]) -> Int {
  var bestDifference: T.Stride.Magnitude?
  var bestIndex = set.endIndex
  for (index, test) in set.enumerated() {
    let difference = value.distance(to: test).magnitude
    if let d = bestDifference {
      if difference < d {
        bestDifference = difference
        bestIndex = index
      }
    } else {
      bestIndex = index
      bestDifference = difference
    }
  }
  return bestIndex
}
