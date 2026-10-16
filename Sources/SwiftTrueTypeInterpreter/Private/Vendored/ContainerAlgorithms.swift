// ===----------------------------------------------------------------------===//
//
// This source file is vendored from the Swift Collections open source project
//
// Copyright (c) 2014 - 2025 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
//
// ===----------------------------------------------------------------------===//

// MARK: - RangeReplaceableCollection.init(copying:)

extension RangeReplaceableCollection {
	/*@inlinable*/
	/*public*/ init(copying source: borrowing Span<Element>) {
		self.init()
		self.reserveCapacity(source.count)
		for index in source.indices {
			self.append(source[index])
		}
	}
}
