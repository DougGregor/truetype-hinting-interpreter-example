extension SwiftTrueTypeInterpreter {
  /// 32-bit element stored on the interpreter's stack.
  struct StackElement {
    private let raw: Int32

    // MARK: Typed initializers

    /// Creates a stack element from an `Int	 value.
    ///
    /// - Parameter int: Integer value to store. Must fit in 32 bits.
    @inline(always) @_transparent
    init(_ int: Int) { self.raw = .init(int) }

    /// Creates a stack element from an unsigned 8-bit value.
    ///
    /// - Parameter uint8: 8-bit unsigned integer to store
    @inline(always) @_transparent
    init(_ uint8: UInt8) { self.raw = .init(uint8) }

    /// Creates a sign-extended stack element from a signed 16-bit value.
    ///
    /// - Parameter eint16: 16-bit signed integer to store
    @inline(always) @_transparent
    init(_ eint16: Int16) { self.raw = .init(eint16) }

    /// Creates a non-sign-extended stack element from a signed 16-bit value.
    ///
    /// - Parameter int16: 16-bit signed integer to store
    @inline(always) @_transparent
    init(withoutExtending int16: Int16) { self.raw = Int32(UInt16(bitPattern: int16)) }

    /// Creates a sign-extended 16-bit stack element from high and low byte values.
    ///
    /// - Parameters:
    ///   - highByte: High byte of the value
    ///   - lowByte: Low byte of the value
    @inline(always) @_transparent
    init(highByte: UInt8, lowByte: UInt8) {
      self.init(Int16(lowByte) | Int16(highByte) << highByte.bitWidth)
    }

    /// Creates a stack element from an unsigned 32-bit value.
    ///
    /// - Parameter uint32: 32-bit unsigned integer to store
    @inline(always) @_transparent
    init(_ uint32: UInt32) { self.raw = .init(bitPattern: uint32) }

    /// Creates a stack element from a 32-bit signed integer.
    ///
    /// - Parameter int32: 32-bit signed integer to store
    @inline(always) @_transparent
    init(_ int32: Int32) { self.raw = int32 }

    /// Creates a stack element from a 26.6 fixed-point number.
    ///
    /// - Parameter f26dot6: Fixed-point value to store
    @inline(always) @_transparent
    init(_ f26dot6: F26Dot6) { self.raw = f26dot6.bitPattern }

    /// Creates a sign-extended stack element from a 2.14 fixed-point number.
    ///
    /// - Parameter f2dot14: Fixed-point value to store
    @inline(always) @_transparent
    init(_ f2dot14: F2Dot14) { self.raw = .init(f2dot14.bitPattern) }

    // MARK: Typed accessors

    /// Extracts the stored value as a `UInt8`, truncating if needed.
    ///
    /// - Returns: 8-bit unsigned integer value
    @inline(always) @_transparent
    func uint8() -> UInt8 { .init(truncatingIfNeeded: raw) }

    /// Extracts the stored value as an `Int`.
    ///
    /// - Returns: Integer value
    @inline(always) @_transparent
    func int() -> Int { .init(self.raw) }

    /// Extracts the stored value as a `UInt32`.
    ///
    /// - Returns: 32-bit unsigned integer value
    @inline(always) @_transparent
    func uint32() -> UInt32 { .init(bitPattern: raw) }

    /// Extracts the stored value as an `Int32`.
    ///
    /// - Returns: 32-bit signed integer value
    @inline(always) @_transparent
    func int32() -> Int32 { raw }

    /// Extracts the stored value as a 26.6 fixed-point number.
    ///
    /// - Returns: Fixed-point value
    @inline(always) @_transparent
    func f26dot6() -> F26Dot6 { .init(bitPattern: raw) }

    /// Extracts the stored value as a 2.14 fixed-point number, truncating if needed.
    ///
    /// - Returns: Fixed-point value
    @inline(always) @_transparent
    func f2dot14() -> F2Dot14 { .init(bitPattern: .init(truncatingIfNeeded: raw)) }
  }
}
