@_spi(ModuleReflection) import Acrylic
import protocol Foundation.LocalizedError
import Shell
import Time

public protocol TestError: LocalizedError, CustomStringConvertible {}

/// A testable environment
public protocol Tests: Testable {
 init()
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
  var typeName = Self.typeConstructorName
  let suffixes = ["Tests", "Test"]

  for suffix in suffixes where typeName.hasSuffix(suffix) {
   guard typeName != suffix else { return suffix }

   let startIndex = typeName.index(typeName.endIndex, offsetBy: -suffix.count)

   typeName.removeSubrange(startIndex...)
   typeName.append(" \(suffix)")
   break
  }
  return typeName
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

  let key = id?.hashValue ?? __key

  do {
   let (shouldUpdate, state) =
    try await Reflection.cacheTestIfNeeded(self, key: key)
   if shouldUpdate {
    try await state.context.update()
   }
  } catch {
   // TODO: should trace error path with state specific error
   // because throwing here will effectively remove the module from the test
   // ultimately, they entire void should be captured, but it's currently
   // required
   // to update modules
   print(
    errorMessage(with: resolvedName, for: error, at: sourceLocation)
   )
   end(error: true)
   throw error
  }

  let state = await Reflection.states[key] as! TestState<Self>
  let context = state.context

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
     print(
      self.errorMessage(
       with: self.resolvedName,
       for: error,
       at: self.sourceLocation
      )
     )
    }
    end(error: true)
   }
   try await cleanUp()
   throw error
  }
 }

 func callAsTestForObjectFromContext(id: AnyHashable? = nil) async throws
  where Self: AnyObject {
  var reference = self
  try await reference.callAsTestFromContext(id: id)
 }
}
