@_spi(ModuleReflection) import Acrylic
import Tests
import XCTest

final class ReflectionTests: XCTestCase {
 func test() async throws {
  let state = try await ModuleState.initialize(with: Graph())
  let context = state.context
  try await context.callAsFunction()
 }
 
 func testWithContext() async throws {
  var graph = Graph()
  try await graph.mutatingCallWithContext()
 }
}

struct Graph: ContextModule {
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
