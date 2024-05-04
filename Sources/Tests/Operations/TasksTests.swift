@_spi(ModuleReflection) import Acrylic
import Tests

struct TestTasks: Testable {
 let breakOnError = true

 var tests: some Testable {
  Test("Background Tasks") { @Reflection in
   let background = Tasks()

   Perform.Async { @Reflection in
    background[queue: 0] = AsyncTask<Output, CancellationError>(
     id: 0, detached: true
    ) {
     for int in [1, 2, 3, 4, 5].reversed() {
      try await sleep(for: .seconds(1))
      print(int, terminator: .space)
     }
    }
   }

   Perform.Async.detached { @Reflection in
    try await background.callAsFunction()
   }

   Assert("Background Task is Running") { @Reflection in
    background.running.notEmpty && background.detached.notEmpty
   }

   Perform.Async.detached {
    try await sleep(for: .seconds(2))
    await background.cancel()
   }

   Assert("Cancel Detached Task") {
    do {
     try await background.wait()
     return false
    } catch _ as CancellationError {
     notify("Succesfully cancelled detached task!")
     return true
    }
   }
  }
  
  /// - Note - results from a module's context are not being stored for now
  ///
  // Identity("Tasks run and return results") {
  //  let tasks = Tasks()
  //
  //  // test normal operation
  //  tasks.queue += [(
  //   0, AsyncTask<(), CancellationError>(id: 0, tasks: tasks) {
  //    for int in [1, 2, 3] {
  //     try await sleep(for: .seconds(0.1))
  //     print(int, terminator: .space)
  //    }
  //   }
  //  )]
  //
  //  // test return operation
  //  tasks.queue += [(
  //   1, AsyncTask<Int, CancellationError>(id: 1, tasks: tasks) {
  //    var sum = 0
  //    for int in [4, 5, 6] {
  //     sum += int
  //     try await sleep(for: .seconds(0.1))
  //     print(int, terminator: .space)
  //    }
  //    print()
  //    return sum
  //   }
  //  )]
  //
  //  let results = try await tasks()?.values.map { $0 }._validResults
  //  return try (results as? [Int]).throwing()
  // } == [15]
  
 }
}
