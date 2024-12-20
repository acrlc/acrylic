@_spi(ModuleReflection) import Acrylic
import Tests
#if !os(Linux)
import ModuleFunctions
#endif
import Shell

/// A module for testing operations that need to be cancelled
struct TestAsyncContext: Testable {
 @Context
 private var should: Bool = true
 @Context
 private var throwError: Bool = false
 @Context
 var count: Int = .zero
 var pressure: Size = .zero

 @discardableResult
 func defect() -> Bool {
  throwError = true
  should = false
  return true
 }

 var void: some Module {
  if should {
   Echo("\nSuccess!\n", color: .green, style: [.bold, .underlined])
  } else if count < 1 {
   Perform.Async("defect", action: { defect() })
   Echo("\nFailure!\n", color: .extended(11), style: [.bold, .underlined])
   Perform.Async { count += 1 }
  } else {
   Perform.Async {
    Map(count: 111) {
     Perform.Async {
      count += 1
     }
     Identity(count)
    }
   }
  }
 }

 var tests: some Testable {
  get async throws {
   let state =
    try await ModuleState.initialize(with: Self())
   let context = state.context
   let index = context.index
   let value = try (index.element as? Self).throwing()

   Perform.Async("Perform & Cancel Tasks") {
    value.should = false
    // call tasks stored on context
    Task.detached {
     try await context.callAsFunction()
    }

    await context.cancel()
    value.should = true
   }

   // check if the task was cancelled
   Assert("Module Update", value.should)
   Assert("Structure Update", !value.throwError)

   Perform.Async("Update Context") {
    value.defect()
    try await context.update(with: .active)
   }

   // assert that the module context was updated to false
   Assert("Module Update", !value.should)
   // assert that module structure was changed
   Assert("Structure Update", value.throwError)

   /// - Note: Results feature not implemented but may return in some form
   /* Test("Assert Context Retained w/ Results") {
     Identity("Results == [true]") {
      try await context.callAsFunction()

      let results =
       try context.results.wrapped.throwing(reason: "results are empty")

      let defectiveIndex =
       try index.index(where: { $0.id as? String == "defect" })
        .throwing(reason: "couldn't find value with id: defect")

      let key = defectiveIndex.key
      return try (
       results.values.first(
        where: { $0.contains(where: { $0.key == key }) }
       )?[key] as? Bool
      )
      .throwing(reason: "results not returned")
     } == true
    } */

   Assert("Benchmark Preparation") {
    value.should = false
    value.throwError = false
    value.count = 1

    try await context.update(with: .active)
    let value = try (context.index.element as? Self).throwing()

    return value.should == false && value.count == 1
   }

   /// A benchmark that tests the speed and cancelling of context operations
   /// - Remark: These aren't interesting examples to benchmark on but they do
   /// give a baseline read on what may happen when cancellation, calls, and
   /// updates are necessary
   ///
   /// The state is determined by the user and framework, itself, but is open
   /// to modification where needed ... These tests are to measure up to the
   /// most extreme cases with precision
   ///
   Benchmarks("ModuleContext Operations") {
    Measure.Async("Update Active Context", warmup: 3, iterations: pressure) {
     try await context.update(with: .active)
    }

    Measure.Async("Call Idle Context", warmup: 3, iterations: pressure) {
     try await context.callAsFunction(with: .idle)
    }

    Measure.Async("Cancel & Call Context", warmup: 3, iterations: pressure) {
     await context.cancel()
     try? await context.callTasks()
    }
   }
  }
 }
}
