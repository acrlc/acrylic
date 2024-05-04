@_spi(ModuleReflection) import Acrylic
@_exported import Acrylic
@_exported import Time

/// A base protocol for calling modules as tests
public protocol TestProtocol: Module {
 associatedtype Output: Sendable
 var testMode: TestMode { get }
 var breakOnError: Bool { get }
 var startMessage: String { get }
 var endMessage: String { get }
 var testName: String? { get }
 var silent: Bool { get set }
 /// Performs before a test starts
 mutating func setUp() async throws
 /// Performs when a test is finished
 mutating func cleanUp() async throws
 /// Performs when a test completes without throwing
 mutating func onCompletion() async throws

 @discardableResult
 mutating func callAsTest() async throws -> Output
}

public extension TestProtocol {
 @_disfavoredOverload
 func setUp() {}
 @_disfavoredOverload
 func cleanUp() {}
 @_disfavoredOverload
 func onCompletion() {}
 @_disfavoredOverload
 var testName: String? { idString }
 @_disfavoredOverload
 var resolvedName: String {
  testName?.wrapped ?? typeConstructorName
 }

 @_disfavoredOverload
 @inlinable
 var silent: Bool { get { false } set {} }

 @_disfavoredOverload
 var breakOnError: Bool { false }

 @_disfavoredOverload
 var testMode: TestMode {
  breakOnError ? .break : .fall
 }

 var startMessage: String {
  let name = resolvedName
  let marker = "[" + "-" + "]"
  if
   name.notEmpty,
   !["test", "tests"].contains(where: { $0 == name.lowercased() }) {
   return marker + .space + "\(name, style: .bold)"
  } else {
   return marker + .space + "\("Tests", style: .boldDim)"
  }
 }

 var endMessage: String {
  let name = resolvedName
  if
   name.notEmpty,
   !["test", "tests"].contains(where: { $0 == name.lowercased() }) {
   return "\("\(name)", style: .bold) \("completed", color: .cyan, style: .bold)"
  } else {
   return "\("Tests", style: .bold) \("completed", color: .cyan, style: .bold)"
  }
 }
}

public enum TestMode: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral {
 case none, `break`, fall
 public init(nilLiteral: ()) {
  self = .none
 }

 public init(booleanLiteral value: Bool) {
  self = value ? .break : .fall
 }

 public static func ?? (lhs: Self, rhs: Self) -> Self {
  lhs == nil ? rhs : lhs
 }

 @inlinable
 public var bool: Bool {
  self == .break ? true : false
 }

 @inlinable
 public static prefix func ! (_ self: Self) -> Bool { !`self`.bool }
}

/* MARK: - Module Conformances */

/// Allow result builder conformance for values conforming to `TestProtocol`
extension [any Module]: TestProtocol {}

public extension TestProtocol where Self: Function {
 @discardableResult
 func callAsTest() async throws -> Output {
  try callAsFunction()
 }
}

public extension TestProtocol where Self: AsyncFunction {
 @discardableResult
 func callAsTest() async throws -> Output {
  try await callAsFunction()
 }
}
