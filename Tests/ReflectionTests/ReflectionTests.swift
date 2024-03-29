@_spi(ModuleReflection) import Acrylic
import XCTest

final class ReflectionTests: XCTestCase {
 func test() async throws {
  let state = ModuleState.initialize(with: Graph())
  let first = state.indices[0][0]
  first.forward { index in
   print(index.start.value)
  }
  print(state.values.map({ $0._flattened.map { $0._id(from: first) } }))

  let context = try XCTUnwrap(first.value._context(from: first))

  try await context.callTasks()
  
  context.cancel()
  try await context.callTasks()

 }
}

struct Graph: Module {
 var void: some Module {
  Group("1") {
   First {
    Second(id: "Hello")
   }
   Third(id: "World!")
  }
 }
}

struct First<Content: Module>: Module {
 @Modular
 var content: () -> Content
 var void: some Module {
  Perform { print("1") }
  content()
 }
}

struct Second: Module {
 var id: String?
 var void: some Module {
  Perform { print("2") }
 }
}

struct Third: Module {
 var id: String?
 var void: some Module {
  Perform { print("3") }
  Perform { print("Done") }
 }
}
