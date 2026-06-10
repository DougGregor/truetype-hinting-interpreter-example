internal import ContainersPreview

// Mirrors `UnsafeBufferPointer.span` from the standard library: a `.ref` accessor that
// returns a `Ref<Pointee>` whose lifetime is the syntactic borrow of `self`. The lifetime
// guarantee is exactly the same as `.span`'s — bounded by the borrow scope of the local
// pointer value, which the compiler tracks even though the pointer itself is `Copyable`
// and `Escapable`.
extension UnsafePointer where Pointee: ~Copyable {
  /// A `Ref<Pointee>` whose lifetime is the borrow of `self`.
  ///
  /// # Safety
  ///
  /// `self` must address an initialized `Pointee` whose storage remains valid for
  /// the borrow of `self`.
  @unsafe
  var ref: Ref<Pointee> {
    @_lifetime(borrow self)
    @inline(__always)
    get {
      // SAFETY: `self` addresses valid storage for the borrow of `self` (caller's
      // contract above). `_overrideLifetime` attaches the result's lifetime to
      // `borrow self` — required because `UnsafePointer` is a trivial value, so
      // `Ref(unsafeAddress:borrowing:)` would otherwise produce a `Ref` with no
      // enforceable lifetime bound.
      let r = unsafe Ref(unsafeAddress: self, borrowing: self)
      return unsafe _overrideLifetime(r, borrowing: self)
    }
  }
}
