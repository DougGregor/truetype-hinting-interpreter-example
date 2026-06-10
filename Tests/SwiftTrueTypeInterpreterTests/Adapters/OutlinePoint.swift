import SwiftTrueTypeInterpreter

// MARK: - OutlinePoint

struct OutlinePoint: Hashable, CustomDebugStringConvertible {
  struct UnscaledCoord: Hashable {
    typealias Component = Int16

    var x: Component
    var y: Component

    static var zero: Self { .init(x: 0, y: 0) }
  }

  var hinted: OutlineCoord
  var scaled: OutlineCoord
  var original: UnscaledCoord

  var onCurve: Bool
  var xMoved: Bool = false
  var yMoved: Bool = false

  var debugDescription: String {
    var result = "OutlinePoint("
    if original != .zero {
      result += "original: .init(x: \(original.x), y: \(original.y)), "
    }
    if scaled == .zero {
      result += "scaled: .zero"
    } else {
      result += "scaled: .init(x: \(Double(scaled.x)), y: \(Double(scaled.y)))"
    }
    if hinted != scaled {
      result += ", "
      if hinted == .zero {
        result += "hinted: .zero"
      } else {
        result += "hinted: .init(x: \(Double(hinted.x)), y: \(Double(hinted.y)))"
      }
    }
    if onCurve {
      result += ", onCurve: true"
    }
    if xMoved {
      result += ", xMoved: true"
    }
    if yMoved {
      result += ", yMoved: true"
    }
    result += ")"
    return result
  }

  init(
    original: UnscaledCoord = .zero,
    scaled: OutlineCoord? = nil,
    hinted: OutlineCoord? = nil,
    onCurve: Bool = false,
    xMoved: Bool = false,
    yMoved: Bool = false
  ) {
    self.original = original
    self.scaled = scaled ?? .init(original)
    self.hinted = hinted ?? self.scaled
    self.onCurve = onCurve
    self.xMoved = xMoved
    self.yMoved = yMoved
  }

  /// Convenience init for testing
  init(
    x: F26Dot6,
    y: F26Dot6,
    onCurve: Bool = false,
    xMoved: Bool = false,
    yMoved: Bool = false
  ) {
    self.init(
      scaled: .init(x: x, y: y),
      hinted: .init(x: x, y: y),
      onCurve: onCurve,
      xMoved: xMoved,
      yMoved: yMoved
    )
  }

  static var zero: Self { .init(scaled: .zero) }

  mutating func moveTo(x: F26Dot6, y: F26Dot6, xMoved: Bool = false, yMoved: Bool = false) {
    self.move(to: .init(x: x, y: y), xMoved: xMoved, yMoved: yMoved)
  }

  mutating func move(to newPosition: OutlineCoord, xMoved: Bool = false, yMoved: Bool = false) {
    self.xMoved = self.xMoved || xMoved
    self.yMoved = self.yMoved || yMoved
    hinted = newPosition
  }
}

// MARK: - Extensions on library types for test convenience

extension SwiftTrueTypeInterpreter.FixedCoord {
  static var zero: Self { .init(x: 0, y: 0) }

  init(bitPatternX x: Fixed.IntegerType, y: Fixed.IntegerType) {
    self.init(x: .init(bitPattern: x), y: .init(bitPattern: y))
  }
}

extension SwiftTrueTypeInterpreter.FixedCoord where Fixed == SwiftTrueTypeInterpreter.F26Dot6 {
  init(_ other: OutlinePoint.UnscaledCoord) {
    self.init(
      x: .init(bitPattern: Fixed.IntegerType(other.x) << Fixed.fractionBits),
      y: .init(bitPattern: Fixed.IntegerType(other.y) << Fixed.fractionBits)
    )
  }
}

extension SwiftTrueTypeInterpreter.FixedVector {
  init(bitPatternX x: Fixed.IntegerType, y: Fixed.IntegerType) {
    self.init(x: .init(bitPattern: x), y: .init(bitPattern: y))
  }

  /// Returns a unit vector scaled from the given parameters
  static func normalizing(x: Fixed, y: Fixed) -> Self {
    Self(x: x, y: y).normalized()
  }

  private func normalized() -> Self {
    let magnitude = magnitude()
    guard magnitude != 0 else {
      return .init(x: 1, y: 0)
    }
    return .init(x: self.x &/ magnitude, y: self.y &/ magnitude)
  }
}
