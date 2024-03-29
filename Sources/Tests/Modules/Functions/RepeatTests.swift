struct TestRepeat: Testable {
 @Context
 var count: Int = 10
 var tests: some Testable {
  Test("Repeat count -= 1") {
   Repeat {
    count -= 1
    return count > .zero
   }
   Assert(count == .zero)
  }
 }
}
