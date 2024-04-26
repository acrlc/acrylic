@_spi(ModuleReflection) import Acrylic
@_spi(TestModuleContext) import Acrylic

// A module for testing the basic running and updating
struct TestContext: Testable {
 @Context
 private var should: Bool = false

 var void: some Module {
  if should {
   Echo("\nHello Acrylic!\n", color: .green, style: [.bold, .underlined])
  } else {
   Echo("\nfatalError()\n", color: .red, style: .bold)
  }
 }

 var tests: some Testable {
  get throws {
   let state = ModuleState.initialize(with: Self())
   let index = try state.indices.first.throwing()
   let value = try (index.element as? Self).throwing()
   let context = state.mainContext

   Perform.Async("Modify State & Context") {
    value.should = false
    // context must be updated or called before reflecting changes to `void`
    await context.update()
   }

   Test("Check Context & Structure") {
    Assert {
     let next = try index.first(where: { $0 is Echo }).throwing()
     // find the first string value of Echo
     let str = try ((next as? Echo)?.items.first as? String).throwing()
     return str == "\nfatalError()\n"
    }

    // assert that the indexed retained it's context
    Assert("Retained Context", !value.should)

    Perform.Async {
     value.should = true
     await context.update()
     try await context.callTestTasks()
    }

    // assert that main module's void was updated
    Assert("Modified Echo") {
     var next = try index.first(where: { $0 is Echo }).throwing()
     // find the first string value of Echo
     let previousStr = try ((next as? Echo)?.items.first as? String)
      .throwing()

     value.should = false

     // must update context after modifying properties
     await context.update()

     next = try index.first(where: { $0 is Echo }).throwing()

     // find the first string value of Echo
     let str = try ((next as? Echo)?.items.first as? String).throwing()

     return str == "\nfatalError()\n" && previousStr == "\nHello Acrylic!\n"
    }
   }
  }
 }
}

extension ModuleContext {
 func callTestTasks() async throws {
  assert(!(calledTask?.isRunning ?? false))
  
  let task = Task {
   let baseIndex = index
   results = .empty
   results[baseIndex.key] = try await tasks()
   let baseIndices = baseIndex.indices
   guard baseIndices.count > 1 else {
    return
   }

   let elements = baseIndices.dropFirst().map {
    ($0, self.cache[$0.key].unsafelyUnwrapped)
   }

   for (index, context) in elements where index.checkedElement != nil {
    results[index.key] = try await context.tasks()
   }
  }

  calledTask = task
  try await task.value
 }
}
