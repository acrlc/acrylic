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
import Command
import Time

@main /// A test for the `Acrylic` framework
struct AcrylicTests: Tests & AsyncCommand {
 @Context
 var breakOnError = true
 @Option
 var pressure: Size = 2

 func setUp() {
  if pressure.rawValue > 11 {
   print()
   notify(
    """
    \n\tLimited test pressure to 13, due to the non-linearity of some \
    structures\n
    """.applying(style: .bold), with: .warning
   )
  }
 }

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

  Test("Operational") {
   if #available(macOS 13, iOS 16, *) {
    TestTasks()
   }

   // limit
   TestMapAsyncDetachedTasks(limit: min(13, pressure.rawValue))
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
    // note: not sure if these warmups do anything at all
    // plus, time is linear and many examples are recursive
    Measure("Sleep 10000µs", warmup: 2, iterations: pressure * 33) {
     usleep(10000)
    }
   }
   Benchmark.Modules(
    "Module Benchmarks", warmup: 2, iterations: pressure * 33
   ) {
    Perform("Sleep 10000µs") { usleep(10000) }
   }

   TestDurationExtensions(pressure: pressure)
  }
 }

 func onCompletion() async {
  print()
  notify(
   String.newline + contextInfo.joined(separator: ",\n"),
   for: "context",
   with: .info
  )
  #if os(WASI) || canImport(SwiftUI)
  // clear previous states / contexts
  Reflection.states.removeAll()
  ModuleContext.cache.removeAll()
  print()

  notify(
   """
   If counter window isn't visible:
   \tMove other windows in order bring to the front
   """
   .applying(style: .bold),
   for: .note
  )

  await MainActor.run { AcrylicTestsApp.main() }
  #endif
 }
}

#if os(WASI) || canImport(SwiftUI)
@available(macOS 13, iOS 16, *)
struct AcrylicTestsApp: App {
 var body: some Scene {
  Window("Count", id: "acrylic.counter") {
   CounterView()
    .frame(maxWidth: 158, maxHeight: 90)
  }
  .windowResizability(.contentSize)
  #if os(macOS)
   .windowStyle(.hiddenTitleBar)
  #endif
 }
}
#endif

extension Size: LosslessStringConvertible {
 public init?(_ description: String) {
  self.init(stringValue: description)
 }
}

public extension Size {
 static func * (lhs: Self, rhs: Self) -> Self {
  Self(rawValue: lhs.rawValue * rhs.rawValue)
 }
}

public typealias TestsCommand = AsyncCommand & Tests
public extension AsyncCommand where Self: Tests {
 func main() async throws {
  do { try await callAsTestFromContext() }
  catch { exit(Int32(error._code)) }
 }
}
