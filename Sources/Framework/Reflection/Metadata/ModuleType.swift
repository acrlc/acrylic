public struct ModuleType: @unchecked Sendable, OptionSet, Hashable {
 public let rawValue: UInt
 public init(rawValue: UInt) { self.rawValue = rawValue }
 public static let module: Self = []
 public static let function = Self(rawValue: 1 << 0)
 public static let async = Self(rawValue: 1 << 1)
 public static let asyncFunction: Self = [async, function]
}

extension ModuleType: CaseIterable, CustomStringConvertible {
 public static let allCases: Set<Self> = [
  module,
  function, async,
  asyncFunction
 ]

 public var description: String {
  switch self {
  case .function: "function"
  case .asyncFunction: "async function"
  default: "module"
  }
 }
}
