@_spi(ModuleReflection) import Acrylic
import protocol Foundation.LocalizedError
import struct Time.Timer

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

public extension Testable {
 func callAsTestFromContext(id: AnyHashable? = nil) async throws {
  let id = id ?? AnyHashable(id)
  let shouldUpdate = try await Reflection.cacheTestIfNeeded(self, id: id)
  let index = Reflection.states[id].unsafelyUnwrapped.indices[0][0]
  let context = index.value._context(from: index).unsafelyUnwrapped

  if shouldUpdate {
   context.update()
   try await context.updateTask?.value
  }

  // can also be called synchronously
  // try await (index.value as! Self).callAsTest()

  let state = Reflection.states[id] as! TestState<Self>
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
   // prepare the test before execution
   try await setUp()

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
