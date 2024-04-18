struct TestRepeat: Testable {
 @Context
 var count: Int = 10
 var tests: some Testable {
  Test("Repeat count -= 1") {
   Repeat.Async { @ModuleContext in
    count -= 1
    return count > .zero
   }
   Assert { @ModuleContext in count == .zero  }
  }
 }
}
