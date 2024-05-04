import Acrylic
import XCTest

final class ModuleTests: XCTestCase {
 func test() async throws {
  @ContextProperty
  var input = ""
  @ContextProperty
  var result = ""

  try Emit($input, result: $result) { input in
   input = "Testing"
   return "void"
  }()

  print(input, result)

  try await Emit.Async($input, result: $result) { input in
   try await sleep(for: .microseconds(250))
   input = "Hello"
   return "World!"
  }()

  print(input, result)
 }
}

// MARK: Test Structures
// A module that recieves a hander and returns recurrent results
protocol Emmiter: Function {
 associatedtype Input: Sendable
 associatedtype Result: Sendable
 /// A binding to the input that indicates the value that must be passed
 /// through the emmiter before a result can be sent
 var input: Input { get nonmutating set }
 var emit: (inout Input) throws -> Result? { get }
 /// A binding to the result being updated
 var result: Result { get nonmutating set }
 @inlinable
 @discardableResult
 func callAsFunction(
  _ result: (inout Input) throws -> Result?
 ) rethrows -> Result?
}

extension Emmiter {
 @_disfavoredOverload
 @inlinable
 @discardableResult
 func callAsFunction(
  _ result: (inout Input) throws -> Result?
 ) rethrows -> Result? {
  try result(&input)
 }

 public func callAsFunction() throws {
  if let result = try callAsFunction(emit) {
   self.result = result
  }
 }
}

/// A handler to run with asynchronous functions
protocol AsyncEmmiter: AsyncFunction {
 associatedtype Input: Sendable
 associatedtype Result: Sendable
 var input: Input { get nonmutating set }
 var emit: (inout Input) async throws -> Result? { get }
 var result: Result { get nonmutating set }
 // can be cached so there should be a mutable version
 func callAsFunction(
  _ result: (inout Input) async throws -> Result?
 ) async rethrows -> Result?
}

extension AsyncEmmiter {
 @_disfavoredOverload
 @inlinable
 @discardableResult
 func callAsFunction(
  _ result: (inout Input) async throws -> Result?
 ) async rethrows -> Result? {
  try await result(&input)
 }

 public func callAsFunction() async throws {
  if let result = try await callAsFunction(emit) {
   self.result = result
  }
 }
}

public struct Emit<Input: Sendable, Result: Sendable>: Emmiter {
 @Context
 var input: Input
 @Context
 var result: Result
 let emit: (inout Input) throws -> Result?

 public init(
  _ input: Context<Input>,
  result: Context<Result>,
  emit: @escaping (inout Input) throws -> Result?
 ) {
  _input = input
  _result = result
  self.emit = emit
 }
}

extension Emit {
 struct Async: AsyncEmmiter {
  @Context
  var input: Input
  @Context
  var result: Result
  let emit: (inout Input) async throws -> Result?

  public init(
   _ input: Context<Input>,
   result: Context<Result>,
   emit: @escaping (inout Input) async throws -> Result?
  ) {
   _input = input
   _result = result
   self.emit = emit
  }
 }
}
