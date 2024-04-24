@_spi(ModuleReflection) import Acrylic
import XCTest

final class ReflectionTests: XCTestCase {
 func test() async throws {
  let state = await ModuleState.initialize(with: Graph())
  let mainContext = state.mainContext
  let first = state.indices[0]
  try first.forward { index in
   let context = try XCTUnwrap(mainContext.cache[index.key])
   XCTAssert(context.index == index)
  }
  
  print(state.values.map { $0.id })

  try await mainContext.callTasks()

  await mainContext.cancel()
  try await mainContext.callTasks()
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
