@_spi(ModuleReflection) import Acrylic

/// A module for testing operations that need to be cancelled
struct TestAsyncContext: Tests {
 @Context
 private var should: Bool = true
 @Context
 private var throwError: Bool = false

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
   let firstIndex = try state.indices[0].first.throwing()
   let index = try firstIndex.index(where: { $0 is Self }).throwing()
   let value = try (index.value as? Self).throwing()
   let id = value._id(from: index)
   let context = try ModuleContext.cache.withLockUnchecked { cache in
    try cache[id].throwing()
   }

   Perform.Async("Perform & Cancel Tasks") {
    value.should = false
    // call tasks stored on context
    context.callAsFunction()
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

   Test("Assert Context Retained") {
    Identity {
     try await state.callAsFunction(context)

     let results = try context.results.throwing(reason: "results are nil")

     let defectiveIndex =
      try index.index(where: { $0.id as? String == "defect" })
       .throwing(reason: "couldn't find value with id: defect")

     let id = defectiveIndex.value._id(from: defectiveIndex)

     return try (results[id] as? [Bool])
      .throwing(reason: "results not returned")
    } == [true]

    // assert that the module context was updated to false
    Assert("Module Update", !value.should)
    // assert that module structure was changed
    Assert("Structure Update", value.throwError)
   }
  }
 }
}
