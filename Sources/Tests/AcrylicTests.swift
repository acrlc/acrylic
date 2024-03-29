@_spi(ModuleReflection) @_exported import Acrylic
import Benchmarks
import Configuration
@_exported import ModuleFunctions
@_exported import Shell
@_exported import Tests
let notify = Configuration.default
#if os(WASI)
import TokamakDOM
#elseif canImport(SwiftUI)
import SwiftUI
#endif

/// A test for the `Acrylic` framework
struct AcrylicTests: Tests {
 @Context
 var breakOnError = true
 @State
 var disabled = true

 var tests: some Testable {
  Test("Assertions / Break") {
   Test("Switch TestMode") {
    Assert(testMode == .break)
    Perform.Async("Switch BreakOnError") { breakOnError = false }
    Assert(testMode == .fall)
   }

   Identity(2 + 2) == 16
   Echo("✔ Failure Asserted", color: .green, style: [.bold])

   Assert(false)
   Echo("✔ Failure Asserted", color: .green, style: [.bold])

   Test("Reset TestMode") {
    Assert(testMode == .fall)
    Perform.Async("Reset BreakOnError") { breakOnError = true }
    Assert(testMode == .break)
   }
  }

  if #available(macOS 13, iOS 16, *) {
   Test("Operational") {
    TestTasks()
   }
  }

  Test("Contextual") {
   TestContext()
   TestAsyncContext()
  }

  Test("Functional") {
   TestMap()
   TestRepeat()
  }

  Test("Benchmarking / Tests") {
   Benchmark("Normal Benchmarks") {
    Measure("Sleep 10000µs", warmup: 2, iterations: 111) { usleep(10000) }
   }
   Benchmark.Modules("Module Benchmarks", warmup: 2, iterations: 111) {
    Perform("Sleep 10000µs") { usleep(10000) }
   }

   TestDurationExtensions()
  }
 }

 func onCompletion() {
  #if os(WASI) || canImport(SwiftUI)
  // clear previous states / contexts
  Reflection.states.removeAll()
  ModuleContext.cache.withLockUnchecked { $0.removeAll() }
  print()

  notify(
   """
   If counter window isn't visible:
   \tMove other windows in order bring to the front
   """
   .applying(style: .bold),
   for: .note
  )
  #endif
 }
}

#if os(WASI) || canImport(SwiftUI)
@available(macOS 13, iOS 16, *)
@main
extension AcrylicTests: App {
 var body: some Scene {
  Window("Count", id: "acrylic.counter") {
   CounterView()
    .task {
     // Run tests within the context of this application
     do {
      try await self.callAsTestFromContext()
      self.disabled = false
     }
     catch {
      exit(Int32(error._code))
     }
    }
    .frame(maxWidth: 158, maxHeight: 90)
    .disabled(self.disabled)
  }
  .windowResizability(.contentSize)
  #if os(macOS)
   .windowStyle(.hiddenTitleBar)
  #endif
 }
}
#else
@main
extension AcrylicTests {}
#endif
