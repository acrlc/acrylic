import Foundation
@_spi(ModuleReflection) import Acrylic
@_exported import ModuleFunctions
@_exported import Shell
import Time

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

extension [any Module]: TestProtocol {}

import Core
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
   return
    "\("\(name)", style: .bold) \("completed", color: .cyan, style: .bold)"
  } else {
   return "\("Tests", style: .bold) \("completed", color: .cyan, style: .bold)"
  }
 }
}

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

public enum TestMode: ExpressibleByNilLiteral, ExpressibleByBooleanLiteral {
 case none, `break`, fall
 public init(nilLiteral: ()) {
  self = .none
 }

 // note: test expressions
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

// - MARK: Testable Protocol
public protocol Testable: TestProtocol {
 associatedtype Testables: Module
 @Modular
 var tests: Testables { get async throws }
}

extension Modules: Testable {
 public var testName: String? { nil }
 public var tests: some Module { self }
}

// TODO: Generate standard conformances
// extension Modular.Map: Testable {}
// extension Modular.Group: Testable {}

public extension Testable {
 @_disfavoredOverload
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
