@_spi(ModuleReflection) import Acrylic
import Core
import Shell
import struct Time.Timer
import Utilities

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
 var tests: some Module { get async throws { try await void } }
}

public extension Testable {
 func test(_ modules: Modules, timer: inout Timer) async throws {
  for module in modules {
   let isTest = module is any TestProtocol
   lazy var test = module as! any TestProtocol

   let name = module.typeConstructorName
   let label: String? = if isTest, let name = test.testName {
    name
   } else {
    module.idString
   }

   var endTime: String

   var endMessage: String {
    "\("after", color: .cyan, style: .bold)" + .space +
     "\(endTime + .space, style: .boldDim)"
   }

   do {
    func setUpTest() async throws {
     try await test.setUp()
     if !test.silent {
      if let label {
       print(
        "\n[ \(label, style: .bold) ]",
        "\("starting", color: .cyan)",
        "\((module is any Tests) ? "Tests" : name, color: .cyan, style: .bold)",
        "❖"
       )
      }
     }
    }

    if
     isTest,
     let test = test as? (any Testable),
     let modules = try await test.tests as? Modules {
     try await setUpTest()
     timer.fire()
     try await self.test(modules, timer: &timer)
    } else {
     var valid = true

     var result: Sendable?

     if let asyncFunction = module as? any AsyncFunction {
      if asyncFunction.detached {
       Task.detached {
        try await asyncFunction.callAsFunction()
       }
       continue
      } else {
       timer.fire()
       result =
        try await asyncFunction.callAsFunction()
      }
     } else if let function = module as? any Function {
      if function.detached {
       Task.detached {
        try function.callAsFunction()
       }
       continue
      } else {
       timer.fire()
       result = try function.callAsFunction()
      }
     } else if isTest {
      try await setUpTest()
      timer.fire()
      result = try await test.callAsTest()
     } else if !module.avoid {
      timer.fire()
      result = try await (module.void as! Modules).callAsFunction()
     }

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
       module.idString == nil
        ? .empty
        : String.arrow.applying(color: .cyan, style: .boldDim) + .space +
        "\(module.idString!, color: .cyan, style: .bold)"
      )
     }

     if let results = result as? [Sendable] {
      result = _getValidResults(results)
      valid = results.filter { ($0 as? [Sendable])?.notEmpty ?? false }.isEmpty
     } else if result is () {
      valid = false
     }

     if valid {
      print(
       String.space,
       "\("return", style: .boldDim)",
       "\("\(result!)".readableRemovingQuotes, style: .bold) ",
       terminator: .empty
      )
     } else {
      print(String.space, terminator: .space)
     }
     print(endMessage)
    }

    if isTest {
     try await test.onCompletion()
     try await test.cleanUp()
    }
   } catch {
    endTime = timer.elapsed.description

    let message = errorMessage(
     with: label ?? name,
     for: error,
     at: isTest ? test.sourceLocation : nil
    )

    print(String.newline + message)
    print(endMessage + .newline)

    if isTest {
     try await test.cleanUp()
    }

    if (isTest && test.testMode == .break) || testMode == .break {
     throw TestsError(
      message: message, sourceLocation: test.sourceLocation
     )
    }
   }
  }
 }

 func errorMessage(
  with identifier: String, for error: Error, at sourceLocation: SourceLocation?
 ) -> String {
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
  var line = String.xmark.applying(color: .red) + .space + message

  if let sourceLocation { line += .newline + sourceLocation.description }

  return line
 }

 @_disfavoredOverload
 mutating func callAsTest() async throws {
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

   var timer = Timer()

   started = true
   start.fire()

   try await test(modules, timer: &timer)
   end()
   try await onCompletion()
   try await cleanUp()
  } catch {
   defer {
    if !started {
     print(
      errorMessage(with: resolvedName, for: error, at: self.sourceLocation)
     )
    }
    end(error: true)
   }
   try await cleanUp()
   throw error
  }
 }

 func callAsTestForObject() async throws
  where Self: AnyObject {
  var reference = self
  try await reference.callAsTest()
 }
}

/// An error designed to be used when testing
struct TestsError: Error, CustomStringConvertible {
 let message: String
 let sourceLocation: SourceLocation?
 public var description: String {
  if let sourceLocation {
   message + .newline + sourceLocation.description
  } else {
   message
  }
 }
}

/// A module for testing modules that allows throwing within an async context
public struct Test<ID: Hashable>: Testable, @unchecked Sendable {
 public var id: ID?
 public var breakOnError: Bool = false
 public var sourceLocation: SourceLocation?
 public var setUpHandler: (() async throws -> ())?
 public var onCompletionHandler: (() async throws -> ())?
 public var cleanUpHandler: (() async throws -> ())?

 @Modular
 var handler: () async throws -> Modules

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
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular handler: @escaping () async throws -> Modules
 ) {
  self.id = id
  self.breakOnError = breakOnError
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  setUpHandler = setUp
  onCompletionHandler = onCompletion
  cleanUpHandler = cleanUp
  self.handler = handler
 }

 init(
  breakOnError: Bool = false,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular handler: @escaping () async throws -> Modules
 ) where ID == EmptyID {
  self.breakOnError = breakOnError
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  setUpHandler = setUp
  onCompletionHandler = onCompletion
  cleanUpHandler = cleanUp
  self.handler = handler
 }
}

/// An assertion test that be combined with a result or called independently
public struct Assertion
<ID: Hashable, A, B: Sendable>: TestProtocol, @unchecked Sendable {
 public var id: ID?
 public var sourceLocation: SourceLocation?
 let lhs: () async throws -> A
 let rhs: () async throws -> B
 /// The comparison operator for `A` and `B`
 var `operator`: (A, B) -> Bool = { _, _ in true }

 fileprivate init(
  id: ID,
  sourceLocation: SourceLocation?,
  lhs: @escaping () async throws -> A,
  operator: @escaping (A, B) -> Bool,
  rhs: @escaping () async throws -> B
 ) {
  self.id = id
  self.sourceLocation = sourceLocation
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  _ id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ lhs: @escaping @autoclosure () throws -> A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: @escaping @autoclosure () throws -> B
 ) where A: Equatable, A == B {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  _ id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ lhs: @escaping @autoclosure () throws -> A,
  _ operator: @escaping (A, B) -> Bool,
  _ rhs: @escaping () async throws -> B
 ) {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ lhs: @escaping () async throws -> A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: @escaping @autoclosure () throws -> B
 ) where A: Equatable, A == B {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ lhs: @escaping () async throws -> A,
  _ operator: @escaping (A, B) -> Bool,
  _ rhs: @escaping @autoclosure () throws -> B
 ) {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ lhs: @escaping @autoclosure () throws -> A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: @escaping @autoclosure () throws -> B
 ) where ID == EmptyID, A: Equatable, A == B {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ lhs: @escaping @autoclosure () throws -> A,
  _ operator: @escaping (A, B) -> Bool,
  _ rhs: @escaping () async throws -> B
 ) where ID == EmptyID {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ lhs: @escaping () async throws -> A,
  _ operator: @escaping (A, B) -> Bool = { $0 == $1 },
  _ rhs: @escaping @autoclosure () throws -> B
 ) where ID == EmptyID, A: Equatable, A == B {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ lhs: @escaping () async throws -> A,
  _ operator: @escaping (A, B) -> Bool,
  _ rhs: @escaping @autoclosure () throws -> B
 ) where ID == EmptyID {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  self.lhs = lhs
  self.rhs = rhs
  self.operator = `operator`
 }

 public struct Error: TestError, @unchecked Sendable {
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
 public func callAsTest() async throws -> B {
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
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  condition: @escaping () async throws -> Bool
 ) {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  lhs = condition
  rhs = {}
  self.operator = { condition, _ in condition }
 }

 init(
  _ id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ condition: @escaping @autoclosure () throws -> Bool
 ) {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  lhs = condition
  rhs = {}
  self.operator = { condition, _ in condition }
 }

 init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  condition: @escaping () async throws -> Bool
 )
  where ID == EmptyID {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  lhs = condition
  rhs = {}
  self.operator = { condition, _ in condition }
 }

 init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ condition: @escaping @autoclosure () throws -> Bool
 )
  where ID == EmptyID {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  lhs = condition
  rhs = {}
  self.operator = { condition, _ in condition }
 }
}

// MARK: - Coalescing Assertions
public extension Function where Output: Sendable & Equatable {
 static func == (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: ==,
   rhs: rhs
  )
 }

 static func == (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: ==,
   rhs: rhs
  )
 }

 static func != (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: !=,
   rhs: rhs
  )
 }
}

public extension Function where Output: Sendable & Comparable {
 static func < (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: <,
   rhs: rhs
  )
 }

 static func < (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: <,
   rhs: rhs
  )
 }

 static func > (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: >,
   rhs: rhs
  )
 }

 static func > (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: >,
   rhs: rhs
  )
 }
}

public extension Function where Output: Sendable & Equatable & Comparable {
 static func <= (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: <=,
   rhs: rhs
  )
 }

 static func <= (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: <=,
   rhs: rhs
  )
 }

 static func >= (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: >=,
   rhs: rhs
  )
 }

 static func >= (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: >=,
   rhs: rhs
  )
 }
}

public extension AsyncFunction where Output: Equatable {
 static func == (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: ==,
   rhs: rhs
  )
 }

 static func == (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: ==,
   rhs: rhs
  )
 }

 static func != (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: !=,
   rhs: rhs
  )
 }
}

public extension AsyncFunction where Output: Comparable {
 static func < (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: <,
   rhs: rhs
  )
 }

 static func < (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: <,
   rhs: rhs
  )
 }

 static func > (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: >,
   rhs: rhs
  )
 }

 static func > (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: >,
   rhs: rhs
  )
 }
}

public extension AsyncFunction where Output: Equatable & Comparable {
 static func <= (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: <=,
   rhs: rhs
  )
 }

 static func <= (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: <=,
   rhs: rhs
  )
 }

 static func >= (
  lhs: Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: >=,
   rhs: rhs
  )
 }

 static func >= (
  lhs: Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id,
   sourceLocation: nil,
   lhs: lhs.callAsFunction,
   operator: >=,
   rhs: rhs
  )
 }
}

public extension TestProtocol where Output: Equatable {
 static func == (
  lhs: consuming Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: ==,
   rhs: rhs
  )
 }

 static func == (
  lhs: consuming Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: ==,
   rhs: rhs
  )
 }

 static func != (
  lhs: consuming Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: !=,
   rhs: rhs
  )
 }

 static func != (
  lhs: consuming Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: !=,
   rhs: rhs
  )
 }
}

public extension TestProtocol where Output: Comparable {
 static func < (
  lhs: consuming Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: <,
   rhs: rhs
  )
 }

 static func < (
  lhs: consuming Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: <,
   rhs: rhs
  )
 }

 static func > (
  lhs: consuming Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: >,
   rhs: rhs
  )
 }

 static func > (
  lhs: consuming Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: >,
   rhs: rhs
  )
 }
}

public extension TestProtocol where Output: Equatable & Comparable {
 static func <= (
  lhs: consuming Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: <=,
   rhs: rhs
  )
 }

 static func <= (
  lhs: consuming Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: <=,
   rhs: rhs
  )
 }

 static func >= (
  lhs: consuming Self, rhs: @escaping @autoclosure () throws -> Output
 ) rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: >=,
   rhs: rhs
  )
 }

 static func >= (
  lhs: consuming Self, rhs: @escaping @autoclosure () async throws -> Output
 ) async rethrows -> Assertion<ID, Output, Output> {
  Assertion(
   id: lhs.id, sourceLocation: lhs.sourceLocation,
   lhs: { try await lhs.callAsTest() },
   operator: >=,
   rhs: rhs
  )
 }
}

/// Executes a void funtion while minimizing compiler optimizations that could
/// interfere with testing
public struct Blackhole<ID: Hashable>: TestProtocol, @unchecked Sendable {
 public var id: ID?
 public var sourceLocation: SourceLocation?
 @inline(never)
 let perform: () async throws -> ()

 public init(
  _ id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ perform: @escaping () async throws -> ()
 ) {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.perform = perform
 }

 public init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ perform: @escaping () async throws -> ()
 ) where ID == EmptyID {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.perform = perform
 }

 public init(
  _ id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ perform: @escaping @autoclosure () throws -> ()
 ) {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.perform = perform
 }

 public init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ perform: @escaping @autoclosure () throws -> ()
 ) where ID == EmptyID {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.perform = perform
 }

 public func callAsTest() async throws { try await perform() }
}

/// Executes a return funtion while minimizing compiler optimizations that could
/// interfere with testing
public struct Identity
<ID: Hashable, Output: Sendable>: TestProtocol, @unchecked Sendable {
 public var id: ID?
 public var sourceLocation: SourceLocation?
 @inline(never)
 public let result: @Sendable () async throws -> Output

 public init(
  _ id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,

  _ result: @Sendable @escaping () async throws -> Output
 ) {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.result = result
 }

 public init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ result: @Sendable @escaping () async throws -> Output
 )
  where ID == EmptyID {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.result = result
 }

 public init(
  _ id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,

  _ result: @Sendable @escaping @autoclosure () throws -> Output
 ) {
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.result = result
 }

 public init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  _ result: @Sendable @escaping @autoclosure () throws -> Output
 )
  where ID == EmptyID {
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )

  self.result = result
 }

 public func callAsTest() async throws -> Output {
  try await result()
 }
}

public struct Catch<ID: Hashable, Failure: Swift.Error & Sendable>:
 @unchecked Sendable, Testable {
 public init(
  id: ID? = nil,
  silent: Bool = true,
  @Modular modules: @Sendable @escaping () async throws -> Modules,
  @Modular onError: @Sendable @escaping (Failure) async throws -> Modules
 ) {
  self.id = id
  self.silent = silent
  self.modules = modules
  self.onError = onError
 }

 public init(
  silent: Bool = true,
  @Modular modules: @Sendable @escaping () async throws -> Modules,
  @Modular onError: @Sendable @escaping (Failure) async throws -> Modules
 )
  where ID == EmptyID {
  self.silent = silent
  self.modules = modules
  self.onError = onError
 }

 public var id: ID?
 public var silent: Bool = true
 @Modular
 let modules: @Sendable () async throws -> Modules
 @Modular
 let onError: (Failure) async throws -> Modules

 public var tests: Modules {
  get async throws {
   do {
    return try await modules()
   } catch let error as Failure {
    return try await onError(error)
   } catch {
    return [Throw(error)]
   }
  }
 }
}

public struct Throw<Failure: Swift.Error & Sendable>: TestProtocol {
 public var silent: Bool = true
 public init(_ error: Failure) {
  self.error = error
 }

 public let error: Failure
 public func callAsTest() throws { throw error }
}
