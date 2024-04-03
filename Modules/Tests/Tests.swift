@_spi(ModuleReflection) import Acrylic
import protocol Foundation.LocalizedError
import struct Time.Timer

public protocol TestError: LocalizedError, CustomStringConvertible {}
/// A testable environment
public protocol Tests: Testable {
 init()
}

public extension Testable {
 func callAsTestFromContext(id: AnyHashable? = nil) async throws {
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

  let id = id ?? AnyHashable(id)
  var shouldUpdate = false
  do {
   shouldUpdate = try await Reflection.cacheTestIfNeeded(self, id: id)
  } catch {
   // TODO: should trace error path with state specific error
   // because throwing here will effectively remove the module from the test
   // ultimately, they entire void should be captured, but it's currently required
   // to update modules
   print(errorMessage(with: resolvedName, for: error))
   end(error: true)
   throw error
  }

  let state = Reflection.states[id] as! TestState<Self>
  let index = state.indices[0]
  let context =
   ModuleContext.cache.withLockUnchecked { $0[index.key] }.unsafelyUnwrapped

  if shouldUpdate {
   context.state.update(context)
   try await context.updateTask?.value
  }

  // can also be called synchronously
  // try await (index.value as! Self).callAsTest()

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
public protocol StaticTests: Tests {
 static func main() async throws
}

extension StaticTests {
 @_disfavoredOverload
 /// Loads the test environment and executes all tests
 static func main() async {
  //   load descriptive modules from context
  do { try await Self().callAsTestFromContext() }
  catch { exit(1) }
 }
}

/* MARK: - Command Line Support */
#if canImport(Command)
import Command

// A test command that calls tests from a stored context
public typealias TestsCommand = AsyncCommand & Tests
public extension AsyncCommand where Self: Tests {
 func main() async throws {
  do { try await callAsTestFromContext() }
  catch {
   exit(Int32(error._code))
  }
 }
}
#endif
