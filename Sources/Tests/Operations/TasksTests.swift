@_spi(ModuleReflection) import Acrylic
import Extensions
import Tests

struct TestTasks: Testable {
 let breakOnError = true

 var tests: some Testable {
  Test("Background Tasks") {
   let background = Tasks()

   Perform.Async {
    background[queue: 0] =
     AsyncTask.detached {
      for int in [1, 2, 3, 4, 5].reversed() {
       try await sleep(for: .seconds(1))
       print(int, terminator: .space)
      }
      return ()
     }
   }

   Perform.Async.detached {
    try await background.callAsFunction()
   }

   // not reading correctly
   Assert("Background Task is Running", !background.detached.isEmpty)

   Perform.Async.detached {
    try await sleep(for: .seconds(2))
    await background.cancel()
   }

   Assert("Cancel Detached Task") {
    do {
     try await background.waitForAll()
     return false
    } catch _ as CancellationError {
     notify("Succesfully cancelled detached task!")
     return true
    }
   }
  }

  /// - Note - results from a module's context are not being stored for now
  ///
  Identity("Tasks run and return results") {
   let tasks = Tasks()

   // test normal operation
   tasks[queue: 0] = AsyncTask {
    for int in [1, 2, 3] {
     try await sleep(for: .seconds(0.1))
     print(int, terminator: .space)
    }
    return
   }

   // test return operation
   tasks[queue: 1] = AsyncTask {
    var sum = 0
    for int in [4, 5, 6] {
     sum += int
     try await sleep(for: .seconds(0.1))
     print(int, terminator: .space)
    }
    print()
    return sum
   }

   var results: [Sendable] = .empty

   for try await (key, _) in tasks {
    if let result = try await tasks[running: key]?.wait() {
     results.append(result)
    }
   }

   try await tasks.waitForAll()

   return try (_getValidResults(results) as? [Int]).throwing()
  } == [15]

  Identity("Waiting Tasks") {
   let tasks = Tasks()

   // test normal operation
   tasks[queue: 1] = AsyncTask.detached {
    print("One", terminator: .space)
    try await sleep(for: .milliseconds(100))
    return 1
   }

   tasks[queue: 2] = AsyncTask {
    try await tasks.waitForDetached()
    print("Two", terminator: .space)
    return 2
   }

   tasks[queue: 3] = AsyncTask {
    try await sleep(for: .milliseconds(100))
    print("Three")
    try await sleep(for: .milliseconds(100))
    return 3
   }

   try await tasks()
   let one = try await (tasks.nextDetached() as? Int).throwing()
   let two = try await (tasks.next() as? Int).throwing()
   let three = try await (tasks.next() as? Int).throwing()

   return [one, two, three]
  } == [1, 2, 3]
 }
}
