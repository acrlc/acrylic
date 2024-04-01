@_spi(ModuleReflection) import Acrylic
// A module for testing the basic running and updating
struct TestContext: Testable {
 @Context
 private var should: Bool = false

 var void: some Module {
  if should {
   Echo("\nHello Acrylic!\n", color: .green, style: [.bold, .underlined])
  } else {
   Echo("\nfatalError()\n", color: .red, style: .bold)
  }
 }

 var tests: some Testable {
  get throws {
   let state = ModuleState.initialize(with: Self())
   let firstIndex = try state.indices[0].first.throwing()
   let index = try firstIndex.index(where: { $0 is Self }).throwing()
   let value = try (index.value as? Self).throwing()
   let key = index.key
   let context = try ModuleContext.cache.withLockUnchecked { cache in
    try cache[key].throwing()
   }

   Perform.Async("Modify State & Context") {
    value.should = false
    // context must be updated or called before reflecting changes to `void`
    context.state.update(context)
   }

   Test("Check Context & Structure") {
    let index = try firstIndex.index(where: { $0 is Self }).throwing()

    Assert {
     let next = try index.first(where: { $0 is Echo }).throwing()
     // find the first string value of Echo
     let str = try ((next as? Echo)?.items.first as? String).throwing()
     return str == "\nfatalError()\n"
    }

    // assert that the indexed retained it's context
    Assert("Retained Context", !value.should)

    Perform.Async {
     value.should = true
     context.state.update(context)
     try await context.callTasks()
    }

    // assert that main module's void was updated
    Assert("Modified Echo") {
     var next = try index.first(where: { $0 is Echo }).throwing()
     // find the first string value of Echo
     let previousStr = try ((next as? Echo)?.items.first as? String).throwing()

     value.should = false

     // must update context after modifying properties
     context.state.update(context)

     next = try index.first(where: { $0 is Echo }).throwing()

     // find the first string value of Echo
     let str = try ((next as? Echo)?.items.first as? String).throwing()

     return str == "\nfatalError()\n" && previousStr == "\nHello Acrylic!\n"
    }
   }
  }
 }
}
