struct TestMapAsyncDetachedTasks: Testable {
 @Context
 var count: Int = .zero
 /// The expected output and mapped wait (in microseconds) for each task
 /// (exponential)
 let limit: Int

 var tests: some Testable {
  Test("Map Async Detached Counter") {
   Identity(count)

   Map(count: limit) { int in
    Map(count: int * int) { int in
     Map(count: int * int) { int in
      Perform.Async(priority: .high, detached: true) {
       try await sleep(for: .microseconds(int))
       count += 1
      }
     }
    }
   }

   Identity(count)
  }
 }
}
