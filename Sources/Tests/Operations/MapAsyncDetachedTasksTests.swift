import Tests
import Foundation

struct TestMapAsyncDetachedTasks: Testable {
 @Context
 var count: Int
 /// The expected output and mapped wait (in microseconds) for each task
 /// (exponential)
 let limit: Int

 var tests: some Testable {
  let expectation = Int(pow(Double(limit), 4))

  Test("Map Async Detached Counter") {
   Identity("Expectation", expectation)
   Identity("Initial Count", count)

   Map(count: limit) {
    Map(count: limit) {
     Map(count: limit) {
      Map(count: limit) {
       Perform.Async(id, priority: .high, detached: true) { 
        count += 1
       }
      }
     }
    }
   }

   Identity("Addition Count", count) == expectation

   Map(count: limit) {
    Map(count: limit) {
     Map(count: limit) {
      Map(count: limit) {
       Perform.Async(id, priority: .high, detached: true) { 
        count -= 1
       }
      }
     }
    }
   }
   
   Identity("Subtraction Count", count) == .zero
   
   Perform.Async("Set Expected Count") { count = expectation }
  }
 }
}
