struct TestMap: Testable {
 @Context
 var count: Int = .zero
 var tests: some Testable {
  Test("Map count += 1") {
   Map(count: 3) {
    Perform.Async { @ModuleContext in count += 1 }
   }
   Assert { @ModuleContext in count == 3 }
  }
 }
}
