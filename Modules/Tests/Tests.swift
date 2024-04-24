@_spi(ModuleReflection) import Acrylic
import protocol Foundation.LocalizedError
import struct Time.Timer

public protocol TestError: LocalizedError, CustomStringConvertible {}
/// A testable environment
public protocol Tests: Testable {
 init()
 /// Performs before a test starts
 mutating func setUp() async throws
 /// Performs when a test is finished
 mutating func cleanUp() async throws
 /// Performs when a test completes without throwing
 mutating func onCompletion() async throws
}

public extension Tests {
 @_disfavoredOverload
 mutating func setUp() async throws {}
 @_disfavoredOverload
 mutating func cleanUp() async throws {}
 @_disfavoredOverload
 mutating func onCompletion() async throws {}
 @_disfavoredOverload
 var testName: String? {
  String(describing: Self.self).replacingOccurrences(of: "Tests", with: "")
 }
}

public extension Testable {
 mutating func callAsTestFromContext(id: AnyHashable? = nil) async throws {
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

  // prepare the test before execution
  try await setUp()

  let key = id ?? (
   !(ID.self is Never.Type) && !(ID.self is EmptyID.Type) &&
    String(describing: self.id).readableRemovingQuotes != "nil" ?
    AnyHashable(self.id) : AnyHashable(
     Swift._mangledTypeName(Self.self) ?? String(describing: Self.self)
    )
  )

  var shouldUpdate = false
  do {
   shouldUpdate = try await Reflection.cacheTestIfNeeded(self, id: key)
  } catch {
   // TODO: should trace error path with state specific error
   // because throwing here will effectively remove the module from the test
   // ultimately, they entire void should be captured, but it's currently
   // required
   // to update modules
   print(errorMessage(with: resolvedName, for: error))
   end(error: true)
   throw error
  }

  let state = await Reflection.states[key] as! TestState<Self>
  let context = state.mainContext

  if shouldUpdate {
   await context.state.update(context)
  }

  do {
   let startMessage = startMessage
   print(startMessage)

   started = true
   start.fire()

   try await context.callTests(with: state)
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

/* MARK: - Executable Support */
/// A test that calls `static func main()` with context support
public protocol StaticTests: Tests {
 static func main() async
}

public extension StaticTests {
 @_disfavoredOverload
 static func main() async {
  //   load descriptive modules from context
  var copy = Self()
  do { try await copy.callAsTestFromContext() }
  catch { exit(Int32(error._code)) }
 }
}

/* MARK: - Command Line Support */
#if canImport(Command)
import Command

/// A test that calls `static func main()` with command and context support
public protocol TestsCommand: Tests & AsyncCommand {}
public extension TestsCommand {
 mutating func main() async throws {
  do { try await callAsTestFromContext() }
  catch {
   exit(Int32(error._code))
  }
 }
}
#endif
