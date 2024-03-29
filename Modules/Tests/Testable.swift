@_spi(ModuleReflection) import Acrylic
@_exported import ModuleFunctions
@_exported import Shell
import struct Time.Timer
import Core

public protocol Testable: TestProtocol {
 associatedtype Testables: Module
 @Modular
 var tests: Testables { get async throws }
}

extension Modules: Testable {
 public var testName: String? { nil }
 public var tests: some Module { self }
}

public extension Testable {
 @_disfavoredOverload
 @inline(__always)
 var tests: some Module { get throws { void } }
}

public extension Testable {
 // swiftlint:disable:next function_body_length cyclomatic_complexity
 func test(_ modules: Modules, timer: inout TimerProtocol) async throws {
  for test in modules {
   let isTest = test is any TestProtocol
   let name = test.typeConstructorName
   let label: String? = if
    let test = test as? any Testable,
    let name = test.testName {
    name
   } else {
    test.idString
   }

   if isTest {
    if let label {
     print(
      "\n[ \(label, style: .bold) ]",
      "\("starting", color: .cyan)",
      "\(name, color: .cyan, style: .bold)",
      "❖"
     )
    } else {
     print(
      "\n[ \(name, color: .cyan, style: .bold) ]", "\("starting", style: .dim)",
      "❖"
     )
    }
   }

   let endTime: String

   var endMessage: String {
    "\("after", color: .cyan, style: .bold)" + .space +
     "\(endTime + .space, style: .boldDim)"
   }

   do {
    if
     let test = test as? any Testable,
     let modules = try await test.tests as? Modules {
     timer.fire()
     try await self.test(modules, timer: &timer)
    } else {
     var valid = true

     var result = try await {
      if let test = test as? any AsyncFunction {
       timer.fire()
       return try await test.callAsyncFunction()
      } else if let test = test as? any Function {
       timer.fire()
       return try await test()
      } else if let test = test as? any TestProtocol {
       timer.fire()
       return try await test.callAsTest()
      } else {
       timer.fire()
       return try await test.callAsFunction()
      }
     }()

     endTime = timer.elapsed.description

     print(
      String.space,
      "\(isTest ? "passed" : "called", color: .cyan, style: .bold)",
      "\(name, color: .cyan)", terminator: .space
     )
     if isTest {
      print(
       String.bullet + .space +
        "\(label == name ? .empty : resolvedName, style: .boldDim)"
      )
     } else {
      print(
       test.idString == nil
        ? .empty
        : String.arrow.applying(color: .cyan, style: .boldDim) + .space +
        "\(test.idString!, color: .cyan, style: .bold)"
      )
     }

     if let results = result as? [Sendable] {
      result = results._validResults
      valid = results.filter { ($0 as? [Sendable])?.notEmpty ?? false }.isEmpty
     } else if result is () {
      valid = false
     }

     if valid {
      print(
       String.space,
       "\("return", style: .boldDim)",
       "\("\(result)".readableRemovingQuotes, style: .bold) ",
       terminator: .empty
      )
     } else {
      print(String.space, terminator: .space)
     }
     print(endMessage)
    }
   } catch {
    endTime = timer.elapsed.description

    let message = errorMessage(with: label ?? name, for: error)

    print(String.newline + message)
    print(endMessage + .newline)

    if testMode == .break {
     throw TestsError(message: message)
    }
   }
  }
 }

 func errorMessage(with identifier: String, for error: Error) -> String {
  let errorHeader = if error is TestError {
   "\(identifier, color: .red, style: .bold)" + .space +
    "\("Failed", color: .red)" + .space +
    String.arrow.applying(color: .red, style: .dim)
  } else {
   "\(identifier, color: .red, style: .bold)" + .space +
    "\("Error", color: .red)" + .space +
    String.arrow.applying(color: .red, style: .dim)
  }

  let message = (errorHeader + .space + error.message)

  return String.xmark.applying(color: .red) + .space + message
 }

 @_disfavoredOverload
 func callAsTest() async throws {
  var start = Timer()
  var started = false

  func end(error: Bool = false) {
   let time = start.elapsed.description
   let end =
    "[" + (error ? String.xmark : .checkmark) + "]" + .space + endMessage

   if !error {
    print()
   }
   print(end, terminator: .empty)

   let secs = " in \(time) "
   echo(secs, style: .boldDim)
  }

  do {
   let tests = try await tests

   let modules = ((tests as? Modules) ?? [tests])._flattened

   // prepare the test before execution
   try await setUp()

   let startMessage = startMessage
   print(startMessage)

   var timer: TimerProtocol = Timer()

   started = true
   start.fire()

   try await test(modules, timer: &timer)
   end()
   try await onCompletion()
   try await cleanUp()
  } catch {
   defer {
    if !started {
     print(self.errorMessage(with: self.resolvedName, for: error))
    }
    end(error: true)
   }
   try await cleanUp()
   throw error
  }
 }
}

/// An error designed to be used when testing
struct TestsError: Error, CustomStringConvertible {
 let message: String
 public var description: String { message }
}

#if swift(<5.10)
/// A module for testing modules that allows throwing within an async context
public struct Test<ID: Hashable, Results: Module>: Testable {
 public var id: ID?
 public var breakOnError: Bool = false
 public var setUpHandler: (() async throws -> ())?
 public var onCompletionHandler: (() async throws -> ())?
 public var cleanUpHandler: (() async throws -> ())?

 @Modular
 var handler: () async throws -> Results

 public func setUp() async throws {
  try await setUpHandler?()
 }

 public func onCompletion() async throws {
  try await onCompletionHandler?()
 }

 public func cleanUp() async throws {
  try await cleanUpHandler?()
 }

 public var tests: Modules {
  get async throws { try await handler() }
 }
}

public extension Test {
 init(
  _ id: ID,
  breakOnError: Bool = false,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular handler: @escaping () async throws -> Results
 ) {
  self.id = id
  self.breakOnError = breakOnError
  setUpHandler = setUp
  onCompletionHandler = onCompletion
  cleanUpHandler = cleanUp
  self.handler = handler
 }

 init(
  breakOnError: Bool = false,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular handler: @escaping () async throws -> Results
 ) where ID == EmptyID {
  self.breakOnError = breakOnError
  setUpHandler = setUp
  onCompletionHandler = onCompletion
  cleanUpHandler = cleanUp
  self.handler = handler
 }
}
#else
/// A module for testing modules that allows throwing within an async context
public struct Test<ID: Hashable, Results: Module>: Testable {
 public var id: ID?
 public var breakOnError: Bool = false
 public var setUpHandler: (() async throws -> ())?
 public var onCompletionHandler: (() async throws -> ())?
 public var cleanUpHandler: (() async throws -> ())?

 @Modular
 var handler: () throws -> Results

 public func setUp() async throws {
  try await setUpHandler?()
 }

 public func onCompletion() async throws {
  try await onCompletionHandler?()
 }

 public func cleanUp() async throws {
  try await cleanUpHandler?()
 }

 // FIXME: Swift 5.10 asks for await on the getter, also declared as `get async throws` within the protocol
 // The only workaround I'm aware of is to use an earlier version of swift
 public var tests: Modules {
  get throws { try handler() }
 }
}

public extension Test {
 init(
  _ id: ID,
  breakOnError: Bool = false,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular handler: @escaping () throws -> Results
 ) {
  self.id = id
  self.breakOnError = breakOnError
  setUpHandler = setUp
  onCompletionHandler = onCompletion
  cleanUpHandler = cleanUp
  self.handler = handler
 }

 init(
  breakOnError: Bool = false,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular handler: @escaping () throws -> Results
 ) where ID == EmptyID {
  self.breakOnError = breakOnError
  setUpHandler = setUp
  onCompletionHandler = onCompletion
  cleanUpHandler = cleanUp
  self.handler = handler
 }
}
#endif

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

/// Executes a void funtion while minimizing compiler optimizations that could
/// interfere with testing
public struct Blackhole<ID: Hashable>: AsyncFunction {
 public var id: ID?
 @inline(never)
 let perform: () async throws -> ()

 public init(_ id: ID, _ perform: @escaping () async throws -> some Any) {
  self.id = id
  self.perform = { _ = perform }
 }

 public init(_ perform: @escaping () async throws -> some Any)
  where ID == EmptyID {
  self.perform = { _ = perform }
 }

 public init(
  _ id: ID,
  _ perform: @escaping @autoclosure () throws -> some Any
 ) {
  self.id = id
  self.perform = { _ = perform }
 }

 public init(_ perform: @escaping @autoclosure () throws -> some Any)
  where ID == EmptyID {
  self.perform = { _ = perform }
 }

 public func callAsyncFunction() async throws { try await perform() }
}

/// Executes a return funtion while minimizing compiler optimizations that could
/// interfere with testing
public struct Identity<ID: Hashable, Output>: AsyncFunction {
 public var id: ID?
 @inline(never)
 let result: () async throws -> Output

 public init(_ id: ID, _ result: @escaping () async throws -> Output) {
  self.id = id
  self.result = result
 }

 public init(_ result: @escaping () async throws -> Output)
  where ID == EmptyID {
  self.result = result
 }

 public init(_ id: ID, _ result: @escaping @autoclosure () throws -> Output) {
  self.id = id
  self.result = result
 }

 public init(_ result: @escaping @autoclosure () throws -> Output)
  where ID == EmptyID {
  self.result = result
 }

 public func callAsyncFunction() async throws -> Output {
  try await result()
 }
}

/* MARK: - Benchmarks Support */
#if canImport(Benchmarks)
import Benchmarks
import Time

/// A module that benchmarks functions
extension Benchmarks: TestProtocol {
 public func callAsTest() async throws {
  try await setUp()

  do {
   let results = try await self()
   // print benchmark results
   for offset in results.keys.sorted() {
    let result = results[offset]!
    let title = result.id ?? "Benchmark " + (offset + 1).description
    let size = result.size
    let average = result.average

    print(
     "[ " + title.applying(color: .cyan, style: .bold) + " ]",
     "\("called \(size) times", style: .boldDim)",
     "\("average", color: .cyan, style: .bold)" + .space +
      "\(average.description + .space, style: .boldDim)"
    )

    let results = result.results._validResults

    if results.notEmpty {
     print(
      "\("return", style: .boldDim)",
      "\("\(results[0])".readableRemovingQuotes, style: .bold)"
     )
    }
   }

   try await onCompletion()
   try await cleanUp()
  } catch {
   try await cleanUp()
   throw error
  }
 }

 init(
  id: ID?,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  benchmarks: @escaping () -> [any BenchmarkProtocol]
 ) {
  self.init()
  self.id = id
  setup = setUp
  complete = onCompletion
  cleanup = cleanUp
  items = benchmarks
 }

 public typealias Modules = BenchmarkModules<ID>
}

/// A module that benchmarks other modules
public struct BenchmarkModules<ID: Hashable>: TestProtocol {
 let benchmarks: Benchmarks<ID>
 public var id: ID? { benchmarks.id }
 public init(
  _ id: ID,
  warmup: Size = 2,
  iterations: Size = 10,
  timeout: Double = 5.0,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular modules: @escaping () -> [any Module]
 ) {
  benchmarks = .init(
   id: id,
   setUp: setUp,
   onCompletion: onCompletion,
   cleanUp: cleanUp,
   benchmarks: {
    let modules = modules()
    return modules.map { module -> any BenchmarkProtocol in
     let id = module.idString
     if let task = module as? any AsyncFunction {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: task.callAsyncFunction
      )
     } else {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: module.callAsFunction
      )
     }
    }
   }
  )
 }

 public init(
  warmup: Size = 2,
  iterations: Size = 10,
  timeout: Double = 5.0,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular modules: @escaping () -> [any Module]
 ) where ID == EmptyID {
  benchmarks = Benchmarks(
   id: nil,
   setUp: setUp,
   onCompletion: onCompletion,
   cleanUp: cleanUp,
   benchmarks: {
    let modules = modules()
    return modules.map { module -> any BenchmarkProtocol in
     let id = module.idString
     if let task = module as? any AsyncFunction {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: task.callAsyncFunction
      )
     } else {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: module.callAsFunction
      )
     }
    }
   }
  )
 }

 public func callAsTest() async throws {
  try await benchmarks.callAsTest()
 }
}

public extension TestProtocol {
 typealias Benchmark<A> = Benchmarks<A> where A: Hashable
 typealias BenchmarkModule<A> = BenchmarkModules<A> where A: Hashable
}
#endif

/* MARK: - Command Support */
#if canImport(Command)
import Command

public typealias TestCommand = AsyncCommand & Testable
public extension AsyncCommand where Self: Testable {
 @_disfavoredOverload
 func main() async throws {
  do { try await callAsTest() }
  catch { exit(Int32(error._code)) }
 }
}
#endif
