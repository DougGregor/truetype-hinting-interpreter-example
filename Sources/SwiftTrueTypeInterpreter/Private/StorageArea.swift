internal import BasicContainers

extension SwiftTrueTypeInterpreter {
  /// Storage area for TrueType hinting program variables.
  ///
  /// Provides indexed storage for 32-bit values that can be read and written
  /// by TrueType instructions during program execution.
  struct StorageArea: ~Copyable {
    /// Array containing the storage area values.
    private(set) /* should be private + testable */ var array: RigidArray<UInt32>

    /// Creates a new storage area with the specified number of locations.
    ///
    /// - Parameter count: Number of storage locations to allocate (defaults to 0)
    init(count: UInt16 = 0) {
      array = .init(repeating: 0, count: Int(count))
    }

    func read(_ location: UInt32) throws(InterpreterError) -> UInt32 {
      guard let location = Int(exactly: location), location < array.count else {
        throw InterpreterError.storageLocationOutOfBounds
      }
      return array[location]
    }

    /// Stores a value at the specified storage location.
    ///
    /// - Parameters:
    ///   - value: Value to store
    ///   - location: Storage location index
    mutating func write(_ value: UInt32, at location: UInt32) throws(InterpreterError) {
      guard let location = Int(exactly: location), location < array.count else {
        throw InterpreterError.storageLocationOutOfBounds
      }
      array[location] = value
    }

    func contents() -> [Int32] {
      Array(copying: array.span.reinterpret(as: Int32.self))
    }
  }
}
