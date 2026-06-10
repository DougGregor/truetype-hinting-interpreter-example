// ===--- SpanExtensions.swift ---------------------------------------------===//
//
// This source file is vendored from the Swift.org open source project
//
// Copyright (c) 2024 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
// ===----------------------------------------------------------------------===//

extension Span where Element: ~Copyable {
  /// This is just standing in for the eventual built-in for-in syntax
  @_transparent
  /*public*/ func _forEach<E: Error>(
    _ body: (borrowing Element) throws(E) -> Void
  ) throws(E) {
    // Simplified for-in over a direct `Span` instance
    var it = 0
    while it < self.count {
      unsafe try body(self[unchecked: it])
      it &+= 1
    }
  }
}
