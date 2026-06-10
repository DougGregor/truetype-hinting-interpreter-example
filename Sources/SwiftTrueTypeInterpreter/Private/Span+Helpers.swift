extension Span where Element: BitwiseCopyable {
  /// Returns a reinterpretation of this span as a span of another type,
  /// which must be fully layout-compatible with `Element`.
  ///
  /// A struct that consists of a single stored property (and does not
  /// introduce any constraints on what values the stored property can hold)
  /// is fully layout compatible with the type of that property, and vice
  /// versa. (And this applies transitively when that type is also a trivial
  /// wrapper.)
  ///
  /// This means that a buffer of the wrapped type is freely reinterpretable
  /// as a buffer of the wrapper, with no elementwise conversion at all.
  ///
  /// Unfortunately we have no way of enforcing that the two input types have
  /// this wrapper/wrappee relationship, so this operation is fundamentally
  /// unsafe.
  @_lifetime(copy self)
  internal func reinterpret<Target: BitwiseCopyable>(
    as _: Target.Type
  ) -> Span<Target> {
    // Note: this assert is incomplete. For example, UInt8 and Bool are both
    // bitwise copyable with the same layout, but not every UInt8 bit
    // pattern is a valid Bool value.
    //
    // Additionally, the assert is also overconstrained; simple wrappers
    // are layout compatible with their contents even if they aren't bitwise
    // copyable.
    //
    // One way to make this fully safe is to introduce a newtype facility
    // to Swift that integrates into the type system.
    assert(
      MemoryLayout<Element>.alignment == MemoryLayout<Target>.alignment
      && MemoryLayout<Element>.size == MemoryLayout<Target>.size
      && MemoryLayout<Element>.stride == MemoryLayout<Target>.stride)
    return unsafe self.bytes._unsafeView(as: Target.self)
  }
}
