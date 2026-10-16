extension SwiftTrueTypeInterpreter {
  /// Execution stack for the TrueType interpreter.
  struct Stack: ~Copyable {
    /// Stack elements storage.
    private(set) var items: UniqueArray<StackElement>

    private let preallocatedSize: Int = 1_024

    private let maximumSize: Int

    /// Creates a new empty stack.
    init() {
      // Bincompat: reference implementation does not enforce maxp stack limit
      self.maximumSize = .init(UInt16.max)

      // The reference interpreter preallocated space for 1024 stack entries,
      // measurements indicate that very few programs use more.
      self.items = .init(capacity: preallocatedSize)
    }

    /// Number of elements currently on the stack.
    @inline(always) @_transparent
    var count: Int {
      items.count
    }

    /// Whether the stack is empty.
    @inline(always) @_transparent
    var isEmpty: Bool {
      items.isEmpty
    }

    private mutating func _grow() throws(InterpreterError) {
      guard items.count &+ 1 <= maximumSize else { throw .stackDepthExceedsLimit }
      let c = Swift.min(
        maximumSize,
        Swift.max(items.count + 1, 2 * items.capacity)
      )
      items.setCapacity(c)
    }

    private mutating func _grow(by newCapacity: Int) throws(InterpreterError) {
      guard items.count &+ newCapacity <= maximumSize else { throw .stackDepthExceedsLimit }
      let c = Swift.min(
        maximumSize,
        Swift.max(items.count &+ newCapacity, 2 * items.capacity)
      )
      items.setCapacity(c)
    }

    /// Pushes multiple byte values onto the stack.
    ///
    /// - Parameter bytes: Byte values to push
    @inline(always) @_transparent
    mutating func push(bytes: Span<UInt8>) throws(InterpreterError) {
      if items.freeCapacity < bytes.count {
        try _grow(by: bytes.count)
      }
      // Capacity is ensured above, so append through an `OutputSpan`, which has no growth path.
      items.edit { output in
        bytes._forEach { byte in
          output.append(StackElement(byte))
        }
      }
    }

    /// Pushes a single element onto the stack.
    ///
    /// - Parameter newItem: Element to push
    @inline(always) @_transparent
    mutating func push(_ newItem: StackElement) throws(InterpreterError) {
      if items.freeCapacity == 0 {
        try _grow()
      }
      // Capacity is ensured above, so append through an `OutputSpan`, which has no growth path.
      // (`UniqueArray.append` includes one, which keeps it from being inlined here.)
      items.edit { $0.append(newItem) }
    }

    /// Pops the top element from the stack.
    ///
    /// - Returns: The popped element
    @inline(always) @_transparent
    @discardableResult mutating func pop() throws(InterpreterError) -> StackElement {
      if items.isEmpty { throw .stackUnderflow }
      return items.removeLast()
    }

    /// Pops multiple elements and passes them to an operation.
    ///
    /// - Parameters:
    ///   - count: Number of elements to pop
    ///   - op: Operation to perform on the popped elements
    /// - Returns: Result from the operation
    @inline(always) @_transparent
    mutating func pop<R: ~Copyable>(
      count: Int,
      _ op: (borrowing Span<StackElement>) throws(InterpreterError) -> R
    ) throws(InterpreterError) -> R {
      guard items.count >= count else {
        throw .stackUnderflow
      }
      defer { items.removeLast(count) }
      return try op(items.span.extracting(last: count))
    }

    @inline(always) @_transparent
    private func _index(belowTop indexBelowTop: UInt32) throws(InterpreterError) -> Int {
      // MINDEX/CINDEX defines the top element of the stack (after popping the index to operate on)
      // as element number 1. Within the internal array, the top element is array.last, or
      // array[array.count - 1]. Valid `indexBelowTop` is `1...items.count`.
      // Stack capacity is capped at `maximumSize` (UInt16.max), so `items.count` always fits in UInt32.
      guard indexBelowTop > 0, indexBelowTop <= UInt32(items.count) else { throw .stackUnderflow }
      return items.count &- Int(indexBelowTop)
    }

    /// Removes an element at the specified index below the top.
    ///
    /// - Parameter indexBelowTop: Index counting from the top (1-based)
    /// - Returns: The removed element
    @inline(always) @_transparent
    mutating func removeAt(indexBelowTop: UInt32) throws(InterpreterError) -> StackElement {
      let index = try _index(belowTop: indexBelowTop)
      return items.remove(at: index)
    }

    /// Peeks at an element at the specified index below the top.
    ///
    /// - Parameter indexBelowTop: Index counting from the top (1-based)
    /// - Returns: The element at the specified position
    @inline(always) @_transparent
    func peek(indexBelowTop: UInt32) throws(InterpreterError) -> StackElement {
      let index = try _index(belowTop: indexBelowTop)
      return items[index]
    }

    /// Swaps the top two elements.
    ///
    @inline(always) @_transparent
    mutating func swap() throws(InterpreterError) {
      guard items.count >= 2 else { throw .stackUnderflow }
      items.swapAt(items.count &- 2, items.count &- 1)
    }

    /// Rolls the top three elements.
    ///
    @inline(always) @_transparent
    mutating func roll() throws(InterpreterError) {
      guard items.count >= 3 else { throw .stackUnderflow }
      items.swapAt(items.count &- 3, items.count &- 2)
      items.swapAt(items.count &- 2, items.count &- 1)
    }
  }
}
