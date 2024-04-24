@_spi(ModuleReflection) import Acrylic

struct TestTasks: Testable {
 let breakOnError = true
 var tests: some Testable {
  Assertion("Tasks run and return results") { 
   let tasks = Tasks()

   // test normal operation
   tasks.queue.append(
    (0, AsyncTask(id: 0, context: .shared) {
     for int in [1, 2, 3] {
      try await sleep(for: .seconds(0.1))
      print(int, terminator: .space)
     }
    })
   )

   // test return operation
   tasks.queue.append(
    (1, AsyncTask(id: 1, context: .shared) {
     var sum = 0
     for int in [4, 5, 6] {
      sum += int
      try await sleep(for: .seconds(0.1))
      print(int, terminator: .space)
     }
     print()
     return sum
    })
   )

   let results = try await tasks()?.values.map { $0 }._validResults

   return try !tasks.isRunning && (results as? [Int]).throwing() == [15]
  }
 }
}
