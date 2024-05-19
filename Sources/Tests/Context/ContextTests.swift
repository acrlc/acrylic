@_spi(ModuleReflection) import Acrylic
import Tests
#if !os(Linux)
import ModuleFunctions
#endif
import Shell

// A module for testing the basic running and updating
struct TestContext: Tests {
 @Context
 private var should: Bool = true

 var void: some Module {
  if should {
   Echo(
    "\nHello Acrylic!\n", color: .green, style: [.bold, .underlined]
   )
  } else {
   Echo("\nfatalError()\n", color: .red, style: .bold)
  }
 }

 var tests: some Testable {
  get async throws {
   let state = try await ModuleState.initialize(with: Self())
   let context = state.context
   let index = context.index
   let value = try (index.element as? Self).throwing()

   /// Modifying the value from a ``Context`` property reflects changes to a
   /// module but must consider a state, before retaining context between
   /// updates to properties or a ``ModuleContext`` which can be called
   /// depending on the module's protocol and specific ``StateActor``
   ///
   Perform.Async("Modify State & Context") {
    value.should = false
    ///
    /// - Important: Context, on updating ``ModuleContext``
    /// Hidden states be updated or called before reflecting changes to `void.`
    /// The default `update` function will infer based on the current state, but
    /// can used to reflect known states, such as `active`, which is known
    /// to cancel, invalidate, and rebuild a ``ModuleContext``
    ///
    /// After cancelling the context's state, which will be set to active, the
    /// context will remain `terminal` until called, set, or properly cancelled.
    try await context.update(with: .active)
   }

   /// - Warning:
   ///  If state is marked as `terminal` a ``CancellationError`` will be thrown.
   /// This is used to dismiss updates when called in succession ...
   Assert("Dismiss Terminal State") {
    do { try await context.update(with: .terminal) }
    catch where error is CancellationError {
     notify("Successfully cancelled update")
     return true
    }
    return false
   }
   
   Test("Check Context & Structure") {
    Assert {
     let next = try index.next.throwing().element
     // find the first string value of Echo
     let str = try ((next as? Echo)?.items.first)?.throwing()
     return str == "\nfatalError()\n"
    }

    // assert that the indexed retained it's context
    Assert("Retained Context", !value.should)

    Perform.Async {
     value.should = true
     try await context.update(with: .active)
     try await context.callTasks()
    }

    // assert that main module's void was updated
    Assert("Modified Echo") {
     var next = try index.next.throwing().element

     // find the first string value of Echo
     let previousStr =
      try ((next as? Echo)?.items.first as? String).throwing()
     value.should = false

     // must update context after modifying properties
     try await context.update(with: .active)
     next = try index.next.throwing().element

     // find the first string value of Echo
     let str =
      try ((next as? Echo)?.items.first as? String).throwing()

     return str == "\nfatalError()\n" && previousStr == "\nHello Acrylic!\n"
    }
   }
  }
 }
}
