@_exported import Acrylic

/// A base protocol for calling modules as tests
public protocol TestProtocol: Module {
 associatedtype Output
 var testMode: TestMode { get }
 var breakOnError: Bool { get }
 var startMessage: String { get }
 var endMessage: String { get }
 var testName: String? { get }

 /// Performs before a test starts
 func setUp() async throws
 /// Performs when a test is finished
 func cleanUp() async throws
 /// Performs when a test completes without throwing
 func onCompletion() async throws

 @discardableResult
 func callAsTest() async throws -> Output
}

public extension TestProtocol {
 @_disfavoredOverload
 func setUp() async throws {}
 @_disfavoredOverload
 func cleanUp() async throws {}
 @_disfavoredOverload
 func onCompletion() async throws {}
 @_disfavoredOverload
 var testName: String? { idString }

 @_disfavoredOverload
 var resolvedName: String {
  testName?.wrapped ?? typeConstructorName
 }

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
 @inline(__always)
 @discardableResult
 func callAsTest() async throws -> Output {
  try await callAsFunction()
 }
}

public extension TestProtocol where Self: AsyncFunction {
 @inline(__always)
 @discardableResult
 func callAsTest() async throws -> Output {
  try await callAsyncFunction()
 }
}

extension Module {
 @inlinable
 var typeConstructorName: String {
  var split =
   Swift._typeName(Self.self).split(separator: ".").dropFirst()
  if split.first == "Modular" {
   split.removeFirst()
  }

  var offset = 0
  for index in split.indices {
   let adjustedIndex = offset + index
   guard adjustedIndex < split.endIndex else {
    break
   }

   var substring = split[adjustedIndex]
   if substring.contains("<") {
    if let splitIndex = substring.firstIndex(where: { $0 == "<" }) {
     substring = substring[...splitIndex]
     substring.removeLast()
     split[adjustedIndex] = substring
     offset += 1

     var remaining = split[(adjustedIndex + offset)...]
     remaining.remove(while: { !$0.hasSuffix(">") })
     remaining.removeLast()
     split.replaceSubrange((adjustedIndex + offset)..., with: remaining)
    }
   }
  }

  if split.count > 1, let last = split.last?.last, last == ">" {
   split.removeLast()
  }

  return split.joined(separator: ".")
 }

 @inlinable
 var idString: String? {
  if !(ID.self is EmptyID.Type), !(ID.self is Never.Type) {
   let id: ID? = if let id = self.id as? (any ExpressibleByNilLiteral) {
    nil ~= id ? nil : self.id
   } else {
    id
   }

   guard let id else {
    return nil
   }

   let string = String(describing: id).readableRemovingQuotes
   if !string.isEmpty, string != "nil" {
    return string
   }
  }
  return nil
 }
}
