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
   let index = try state.indices.first.throwing()
   let value = try (index.element as? Self).throwing()
   let key = index.key
   let context = try ModuleContext.cache[key].throwing()

   Perform.Async("Modify State & Context") { @ModuleContext in
    value.should = false
    // context must be updated or called before reflecting changes to `void`
    context.state.update(context)
   }

   Test("Check Context & Structure") {
    Assert {
     let next = try index.first(where: { $0 is Echo }).throwing()
     // find the first string value of Echo
     let str = try ((next as? Echo)?.items.first as? String).throwing()
     return str == "\nfatalError()\n"
    }

    // assert that the indexed retained it's context
    Assert("Retained Context") { @ModuleContext in !value.should }

    Perform.Async { @ModuleContext in
     value.should = true
     context.state.update(context)
     try await context.callTasks()
    }

    // assert that main module's void was updated
    Assert("Modified Echo") { @ModuleContext in
     var next = try index.first(where: { $0 is Echo }).throwing()
     // find the first string value of Echo
     let previousStr = try ((next as? Echo)?.items.first as? String)
      .throwing()

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
