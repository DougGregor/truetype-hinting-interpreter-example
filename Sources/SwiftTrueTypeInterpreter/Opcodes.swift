/// Function signature for opcode implementation functions.
typealias JumpTableFunc =
@Sendable @convention(thin) (inout SwiftTrueTypeInterpreter.State, UInt8)
throws(SwiftTrueTypeInterpreter.InterpreterError) -> Void

extension SwiftTrueTypeInterpreter {
  /// TrueType hinting program opcodes and their implementations.
  enum Opcode: UInt8, CaseIterable {
    case SVTCA_Y = 0x00
    case SVTCA_X = 0x01
    case SPVTCA_Y = 0x02
    case SPVTCA_X = 0x03
    case SFVTCA_Y = 0x04
    case SFVTCA_X = 0x05
    case SPVTL = 0x06
    case SFVTL = 0x08
    case SPVFS = 0x0A
    case SFVFS = 0x0B
    case GPV = 0x0C
    case GFV = 0x0D
    case SFVTPV = 0x0E
    case ISECT = 0x0F
    case SRP0 = 0x10
    case SRP1 = 0x11
    case SRP2 = 0x12
    case SZP0 = 0x13
    case SZP1 = 0x14
    case SZP2 = 0x15
    case SZPS = 0x16
    case SLOOP = 0x17
    case RTG = 0x18
    case RTHG = 0x19
    case SMD = 0x1A
    case ELSE = 0x1B
    case JMPR = 0x1C
    case SCVTCI = 0x1D
    case SSWCI = 0x1E
    case SSW = 0x1F
    case DUP = 0x20
    case POP = 0x21
    case CLEAR = 0x22
    case SWAP = 0x23
    case DEPTH = 0x24
    case CINDEX = 0x25
    case MINDEX = 0x26
    case ALIGNPTS = 0x27
    case UTP = 0x29
    case LOOPCALL = 0x2A
    case CALL = 0x2B
    case FDEF = 0x2C
    case ENDF = 0x2D
    case MDAP = 0x2E
    case IUP_Y = 0x30
    case IUP_X = 0x31
    case SHP = 0x32
    case SHC = 0x34
    case SHZ = 0x36
    case SHPIX = 0x38
    case IP = 0x39
    case MSIRP = 0x3A
    case ALIGNRP = 0x3C
    case RTDG = 0x3D
    case MIAP = 0x3E
    case NPUSHB = 0x40
    case NPUSHW = 0x41
    case WS = 0x42
    case RS = 0x43
    case WCVTP = 0x44
    case RCVT = 0x45
    case GC = 0x46
    case SCFS = 0x48
    case MD = 0x49
    case MPPEM = 0x4B
    case MPS = 0x4C
    case FLIPON = 0x4D
    case FLIPOFF = 0x4E
    case DEBUG = 0x4F
    case LT = 0x50
    case LTEQ = 0x51
    case GT = 0x52
    case GTEQ = 0x53
    case EQ = 0x54
    case NEQ = 0x55
    case ODD = 0x56
    case EVEN = 0x57
    case IF = 0x58
    case EIF = 0x59
    case AND = 0x5A
    case OR = 0x5B
    case NOT = 0x5C
    case DELTAP1 = 0x5D
    case SDB = 0x5E
    case SDS = 0x5F
    case ADD = 0x60
    case SUB = 0x61
    case DIV = 0x62
    case MUL = 0x63
    case ABS = 0x64
    case NEG = 0x65
    case FLOOR = 0x66
    case CEILING = 0x67
    case ROUND = 0x68
    case NROUND = 0x6C
    case WCVTF = 0x70
    case DELTAP2 = 0x71
    case DELTAP3 = 0x72
    case DELTAC1 = 0x73
    case DELTAC2 = 0x74
    case DELTAC3 = 0x75
    case SROUND = 0x76
    case S45ROUND = 0x77
    case JROT = 0x78
    case JROF = 0x79
    case ROFF = 0x7A
    case Reserved = 0x7B
    case RUTG = 0x7C
    case RDTG = 0x7D
    case SANGW = 0x7E
    case AA = 0x7F
    case FLIPPT = 0x80
    case FLIPRGON = 0x81
    case FLIPRGOFF = 0x82
    case SCANCTRL = 0x85
    case SDPVTL = 0x86
    case GETINFO = 0x88
    case IDEF = 0x89
    case ROLL = 0x8A
    case MAX = 0x8B
    case MIN = 0x8C
    case SCANTYPE = 0x8D
    case INSTCTRL = 0x8E
    case GETVARIATION = 0x91
    case GETDATA = 0x92
    case PUSHB = 0xB0
    case PUSHW = 0xB8
    case MDRP = 0xC0
    case MIRP = 0xE0

    /// Returns the range of instructions covered by this opcode.
    ///
    /// - Returns: Closed range of instruction values
    var range: ClosedRange<RawValue> {
      switch self {
      case .SPVTL: 0x06...0x07
      case .SFVTL: 0x08...0x09
      case .MDAP: 0x2E...0x2F
      case .SHP: 0x32...0x33
      case .SHC: 0x34...0x35
      case .SHZ: 0x36...0x37
      case .MSIRP: 0x3A...0x3B
      case .MIAP: 0x3E...0x3F
      case .GC: 0x46...0x47
      case .MD: 0x49...0x4A
      case .ROUND: 0x68...0x6B
      case .NROUND: 0x6C...0x6F
      case .SDPVTL: 0x86...0x87
      case .PUSHB: 0xB0...0xB7
      case .PUSHW: 0xB8...0xBF
      case .MDRP: 0xC0...0xDF
      case .MIRP: 0xE0...0xFF
      default: rawValue...rawValue
      }
    }

    /// Returns the range of instructions covered by this opcode as integers.
    ///
    /// - Returns: Closed range of instruction values as Int
    var intRange: ClosedRange<Int> {
      let raw = range
      return Int(raw.lowerBound)...Int(raw.upperBound)
    }

    /// Returns the number of instructions covered by this opcode.
    ///
    /// - Returns: Count of instructions in the opcode's range
    var count: Int { range.count }

    /// Returns the implementation function for this opcode.
    fileprivate var impl: JumpTableFunc {
      switch self {
      case .AA: impl_AA
      case .ABS: impl_ABS
      case .ADD: impl_ADD
      case .ALIGNPTS: impl_ALIGNPTS
      case .ALIGNRP: impl_ALIGNRP
      case .AND: impl_AND
      case .CALL: impl_CALL
      case .CEILING: impl_CEILING
      case .CINDEX: impl_CINDEX
      case .CLEAR: impl_CLEAR
      case .DEBUG: impl_DEBUG
      case .DELTAC1: impl_DELTAC1
      case .DELTAC2: impl_DELTAC2
      case .DELTAC3: impl_DELTAC3
      case .DELTAP1: impl_DELTAP1
      case .DELTAP2: impl_DELTAP2
      case .DELTAP3: impl_DELTAP3
      case .DEPTH: impl_DEPTH
      case .DIV: impl_DIV
      case .DUP: impl_DUP
      case .EIF: impl_EIF
      case .ELSE: impl_ELSE
      case .ENDF: impl_ENDF
      case .EQ: impl_EQ
      case .EVEN: impl_EVEN
      case .FDEF: impl_FDEF
      case .FLIPOFF: impl_FLIPOFF
      case .FLIPON: impl_FLIPON
      case .FLIPPT: impl_FLIPPT
      case .FLIPRGOFF: impl_FLIPRGOFF
      case .FLIPRGON: impl_FLIPRGON
      case .FLOOR: impl_FLOOR
      case .GC: impl_GC
      case .GETDATA: impl_GETDATA
      case .GETINFO: impl_GETINFO
      case .GETVARIATION: impl_GETVARIATION
      case .GFV: impl_GFV
      case .GPV: impl_GPV
      case .GT: impl_GT
      case .GTEQ: impl_GTEQ
      case .IDEF: impl_IDEF
      case .IF: impl_IF
      case .INSTCTRL: impl_INSTCTRL
      case .IP: impl_IP
      case .ISECT: impl_ISECT
      case .IUP_X: impl_IUPX
      case .IUP_Y: impl_IUPY
      case .JMPR: impl_JMPR
      case .JROF: impl_JROF
      case .JROT: impl_JROT
      case .LOOPCALL: impl_LOOPCALL
      case .LT: impl_LT
      case .LTEQ: impl_LTEQ
      case .MAX: impl_MAX
      case .MD: impl_MD
      case .MDAP: impl_MDAP
      case .MDRP: impl_MDRP
      case .MIAP: impl_MIAP
      case .MIN: impl_MIN
      case .MINDEX: impl_MINDEX
      case .MIRP: impl_MIRP
      case .MPPEM: impl_MPPEM
      case .MPS: impl_MPS
      case .MSIRP: impl_MSIRP
      case .MUL: impl_MUL
      case .NEG: impl_NEG
      case .NEQ: impl_NEQ
      case .NOT: impl_NOT
      case .NPUSHB: impl_NPUSHB
      case .NPUSHW: impl_NPUSHW
      case .NROUND: impl_NROUND
      case .ODD: impl_ODD
      case .OR: impl_OR
      case .POP: impl_POP
      case .PUSHB: impl_PUSHB
      case .PUSHW: impl_PUSHW
      case .RCVT: impl_RCVT
      case .RDTG: impl_RDTG
      case .Reserved: impl_InstructionIllegal  // reserved for data compression
      case .ROFF: impl_ROFF
      case .ROLL: impl_ROLL
      case .ROUND: impl_ROUND
      case .RS: impl_RS
      case .RTDG: impl_RTDG
      case .RTG: impl_RTG
      case .RTHG: impl_RTHG
      case .RUTG: impl_RUTG
      case .S45ROUND: impl_S45ROUND
      case .SANGW: impl_SANGW
      case .SCANCTRL: impl_SCANCTRL
      case .SCANTYPE: impl_SCANTYPE
      case .SCFS: impl_SCFS
      case .SCVTCI: impl_SCVTCI
      case .SDB: impl_SDB
      case .SDPVTL: impl_SDPVTL
      case .SDS: impl_SDS
      case .SFVFS: impl_SFVFS
      case .SFVTCA_X: impl_SFVTCA_X
      case .SFVTCA_Y: impl_SFVTCA_Y
      case .SFVTL: impl_SFVTL
      case .SFVTPV: impl_SFVTPV
      case .SHC: impl_SHC
      case .SHP: impl_SHP
      case .SHPIX: impl_SHPIX
      case .SHZ: impl_SHZ
      case .SLOOP: impl_SLOOP
      case .SMD: impl_SMD
      case .SPVFS: impl_SPVFS
      case .SPVTCA_X: impl_SPVTCA_X
      case .SPVTCA_Y: impl_SPVTCA_Y
      case .SPVTL: impl_SPVTL
      case .SROUND: impl_SROUND
      case .SRP0: impl_SRP0
      case .SRP1: impl_SRP1
      case .SRP2: impl_SRP2
      case .SSW: impl_SSW
      case .SSWCI: impl_SSWCI
      case .SUB: impl_SUB
      case .SVTCA_X: impl_SVTCA_X
      case .SVTCA_Y: impl_SVTCA_Y
      case .SWAP: impl_SWAP
      case .SZP0: impl_SZP0
      case .SZP1: impl_SZP1
      case .SZP2: impl_SZP2
      case .SZPS: impl_SZPS
      case .UTP: impl_UTP
      case .WCVTF: impl_WCVTF
      case .WCVTP: impl_WCVTP
      case .WS: impl_WS
      }
    }

    /// Extracts immediate value from instruction within this opcode's range.
    ///
    /// - Parameter instruction: Instruction byte to decode
    /// - Returns: Immediate value (0-based offset within range)
    @inline(always)
    func immediate(for instruction: UInt8) -> Int {
      assert(self.range.contains(instruction))
      return .init(instruction &- self.rawValue)
    }

    /// Decodes count value from instruction (1-based).
    ///
    /// - Parameter instruction: Instruction byte to decode
    /// - Returns: Count value (1-based offset within range)
    @inline(always)
    func decodeCount(from instruction: UInt8) -> Int {
      .init(instruction &- self.rawValue) &+ 1
    }
  }

  /// Jump table for the interpreter execution loop.
  static let dispatch: [JumpTableFunc] = {
    // The impl_* references below are hoisted into local `let` bindings rather than
    // passed directly into `Array.init(repeating:)` / subscript assignment. Under
    // Swift 6 mode the inline form fails with
    // "lifetime-dependent variable 'state' escapes its scope" because `State` is
    // `~Escapable` and the lifetime checker can't reason through the implicit
    // function-value conversion at the call site. Binding to a local of explicit
    // `JumpTableFunc` type performs the conversion in a context the checker accepts.
    let patch: JumpTableFunc = impl_InstructionPatch
    let pushB0: JumpTableFunc = impl_PUSHB0
    let pushW0: JumpTableFunc = impl_PUSHW0
    var result: [JumpTableFunc] = .init(repeating: patch, count: Int(UInt8.max) + 1)
    for op in Opcode.allCases {
      result.replaceSubrange(op.intRange, with: repeatElement(op.impl, count: op.count))
    }
    result[Int(SwiftTrueTypeInterpreter.Opcode.PUSHB.rawValue)] = pushB0
    result[Int(SwiftTrueTypeInterpreter.Opcode.PUSHW.rawValue)] = pushW0
    return result
  }()
}
