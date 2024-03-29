// @_exported import LogMacros
/* - TODO: Improve testing interface
 - Use indices to determine and track the point of failure
 - Create test metadata, time, and measure
 - Create test macros to check at compile time
 - Run async throwing stream to return each test result
 */
import protocol Foundation.LocalizedError
@_exported import ModuleFunctions
public protocol TestError: LocalizedError, CustomStringConvertible {}
/// A testable environment
public protocol Tests: Testable {
 init()
}

public extension Tests {
 @_disfavoredOverload
 /// Loads the test environment and executes all tests
 static func main() async {
  //   load descriptive modules from context
  //   TODO: Prioritize tests and store results to create an overview
  do { try await Self().callAsTest() }
  catch { exit(1) }
 }
}

/// An assertion test that be combined with a result or called independently
public struct Assertion<ID: Hashable, A, B>: AsyncFunction {
 public var id: ID?
 let lhs: () async throws -> A
 let rhs: () async throws -> B
 /// The comparison operator for `A` and `B`
 var `operator`: (A, B) -> Bool = { _, _ in true }

 public init(
  id: ID,
  _ lhs: A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: B
 ) where A: Equatable, A == B {
  self.id = id
  self.lhs = { lhs }
  self.rhs = { rhs }
  self.operator = `operator`
 }

 public init(
  _ id: ID,
  _ lhs: @escaping @autoclosure () throws -> A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: @escaping () async throws -> B
 ) where A: Equatable, A == B {
  self.id = id
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  _ id: ID,
  _ lhs: @escaping @autoclosure () throws -> A,
  _ operator: @escaping (A, B) -> Bool,
  _ rhs: @escaping () async throws -> B
 ) {
  self.id = id
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  id: ID,
  _ lhs: @escaping () async throws -> A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: @escaping @autoclosure () throws -> B
 ) where A: Equatable, A == B {
  self.id = id
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  id: ID,
  _ lhs: @escaping () async throws -> A,
  _ operator: @escaping (A, B) -> Bool,
  _ rhs: @escaping @autoclosure () throws -> B
 ) {
  self.id = id
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  _ lhs: A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: B
 ) where ID == EmptyID, A: Equatable, A == B {
  self.lhs = { lhs }
  self.rhs = { rhs }
  self.operator = `operator`
 }

 public init(
  _ lhs: @escaping @autoclosure () throws -> A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: @escaping () async throws -> B
 ) where ID == EmptyID, A: Equatable, A == B {
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  _ lhs: @escaping @autoclosure () throws -> A,
  _ operator: @escaping (A, B) -> Bool,
  _ rhs: @escaping () async throws -> B
 ) where ID == EmptyID {
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  _ lhs: @escaping () async throws -> A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: @escaping @autoclosure () throws -> B
 ) where ID == EmptyID, A: Equatable, A == B {
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  _ lhs: @escaping () async throws -> A,
  _ operator: @escaping (A, B) -> Bool,
  _ rhs: @escaping @autoclosure () throws -> B
 ) where ID == EmptyID {
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public struct Error: TestError {
  let lhs: A
  let rhs: B
  public var errorDescription: String? {
   if A.self is Bool.Type, B.self is Swift.Void.Type {
    "Asserted condition wasn't met"
   } else {
    """
    \n\tExpected condition from \(lhs, style: .underlined) \
    to \(rhs, style: .underlined) wasn't met
    """
   }
  }
 }

 @discardableResult
 public func callAsyncFunction() async throws -> B {
  let lhs = try await lhs()
  let rhs = try await rhs()

  guard self.operator(lhs, rhs) else {
   throw Error(lhs: lhs, rhs: rhs)
  }

  return rhs
 }
}

public extension TestProtocol {
 typealias Assert<ID, A, B> = Assertion<ID, A, B> where ID: Hashable
}

public extension Assertion where A == Bool, B == Swift.Void {
 init(
  _ id: ID,
  condition: @escaping () async throws -> Bool
 ) {
  self.id = id
  lhs = condition
  rhs = {}
  self.operator = { condition, _ in condition }
 }

 init(
  _ id: ID, _ condition: @escaping @autoclosure () throws -> Bool
 ) {
  self.id = id
  lhs = condition
  rhs = {}
  self.operator = { condition, _ in condition }
 }

 init(condition: @escaping () async throws -> Bool)
  where ID == EmptyID {
  lhs = condition
  rhs = {}
  self.operator = { condition, _ in condition }
 }

 init(_ condition: @escaping @autoclosure () throws -> Bool)
  where ID == EmptyID {
  lhs = condition
  rhs = {}
  self.operator = { condition, _ in condition }
 }
}

// MARK: - Coalescing Assertions
public extension Function where Output: Equatable {
 static func == (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsFunction, ==, rhs)
 }

 static func != (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsFunction, !=, rhs)
 }
}

public extension AsyncFunction where Output: Equatable {
 static func == (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsyncFunction, ==, rhs)
 }

 static func != (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsyncFunction, !=, rhs)
 }
}

public extension Function where Output: Comparable {
 static func < (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsFunction, <, rhs)
 }

 static func > (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsFunction, >, rhs)
 }
}

public extension AsyncFunction where Output: Comparable {
 static func < (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsyncFunction, <, rhs)
 }

 static func > (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsyncFunction, >, rhs)
 }
}

public extension Function where Output: Equatable & Comparable {
 static func <= (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsFunction, <=, rhs)
 }

 static func >= (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsFunction, >=, rhs)
 }
}

public extension AsyncFunction where Output: Equatable & Comparable {
 static func <= (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsyncFunction, <=, rhs)
 }

 static func >= (lhs: Self, rhs: Output) -> Assertion<ID, Output, Output> {
  Assertion(id: lhs.id, lhs.callAsyncFunction, >=, rhs)
 }
}
