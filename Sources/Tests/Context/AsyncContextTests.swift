@_spi(ModuleReflection) import Acrylic

/// A module for testing operations that need to be cancelled
struct TestAsyncContext: Tests {
 @Context
 private var should: Bool = true
 @Context
 private var throwError: Bool = false

 @ModuleContext
 @discardableResult
 func defect() async -> Bool {
  throwError = true
  should = false
  return true
 }

 var void: some Module {
  if should {
   Echo("\nSuccess!\n", color: .green, style: [.bold, .underlined])
  } else {
   Perform.Async("defect", action: defect)
   Echo("\nFailure!\n", color: .extended(11), style: [.bold, .underlined])
  }
 }

 var tests: some Testable {
  get throws {
   let state = ModuleState.initialize(with: Self())
   let index = try state.indices.first.throwing()
   let value = try (index.element as? Self).throwing()
   let key = index.key
   let context = try ModuleContext.cache[key].throwing()

   Perform.Async("Perform & Cancel Tasks") { @ModuleContext in
    value.should = false
    // call tasks stored on context
    Task.detached {
     try await context.callAsFunction()
    }
    context.cancel()
    // check if tasks were cancelled (could throw if performance deviates)
    try (!context.isRunning).throwing()
    value.should = true
   }

   // check if the task was cancelled
   Assert("Module Update", value.should)
   Assert("Structure Update", !value.throwError)

   Perform.Async("Update Context") {
    await value.defect()
    try (!context.isRunning).throwing()
   }

   // assert that the module context was updated to false
   Assert("Module Update", !value.should)
   // assert that module structure was changed
   Assert("Structure Update", value.throwError)

   Test("Assert Context Retained w/ Results") {
    Identity { @ModuleContext in
     try await state.callAsFunction(context)

     let results =
      try context.results.wrapped.throwing(reason: "results are empty")

     let defectiveIndex =
      try index.index(where: { $0.id as? String == "defect" })
       .throwing(reason: "couldn't find value with id: defect")

     let key = defectiveIndex.key
     return try (results[key] as? [Bool])
      .throwing(reason: "results not returned")
    } == [true]
   }
  }
 }
}
