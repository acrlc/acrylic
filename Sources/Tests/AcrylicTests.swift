@_spi(ModuleReflection) @_exported import Acrylic
import Command
import Configuration
import Shell
import Tests
#if os(WASI)
import TokamakDOM
#elseif canImport(SwiftUI)
import SwiftUI
#endif

@main /// A test for the `Acrylic` framework
struct AcrylicTests: TestsCommand {
 @Option
 var pressure: Size = 5
 @Option
 var iterations: Int = 1

 @Context
 var breakOnError = true
 @Context
 var asyncMapCount: Int = .zero
 @Context
 var count: Int = .zero
 @Context
 var concurrentCount: Int = .zero

 let start: Tick = .now

 mutating func setUp() {
  notify("Startup time is", Tick.now.elapsedTime(since: start))

  if pressure.rawValue > 13 {
   print()
   notify(
    """
    \n\tLimited test pressure to 13, due to the non-linearity of some \
    structures\n
    """.applying(style: .bold), with: .warning
   )
   pressure = 13
  } else if pressure.rawValue < 1 {
   print()
   notify(
    """
    \nSetting test pressure to minimum value of 1\n
    """.applying(style: .bold), with: .warning
   )
   pressure = 1
  }
 }

 var tests: some Testable {
  for _ in 0 ..< iterations {
   Benchmarks("Normal Benchmarks") {
    // note: not sure if these warmups do anything at all
    // plus, time is linear and many examples are recursive
    Measure("Sleep 111µs", warmup: 2, iterations: pressure * 11) {
     usleep(111)
    }
   }
   Benchmark.Modules(
    "Module Benchmarks", warmup: 2, iterations: pressure * 11
   ) {
    Perform("Sleep 111µs") { usleep(111) }
   }

   let propertiesBenchmarkSize: Size = pressure * 111

   /// Measures the speed of reads and writes using `Context` properties
   Benchmarks(
    "Context Property Benchmarks",
    onCompletion: {
     notify("Current count is", count, with: .info)
    }
   ) {
    Measure(
     "Read",
     warmup: 2,
     iterations: propertiesBenchmarkSize,
     perform: { identity(count) }
    )

    Measure(
     "Write += 1", warmup: 2, iterations: propertiesBenchmarkSize,
     perform: { blackHole(count += 1) }
    )
   }

   Benchmarks(
    "Concurrent Property Benchmarks",
    onCompletion: {
     notify("Concurrent count is", concurrentCount, with: .info)
    }
   ) {
    let concurrentIterations = 0 ..< count

    Measure.Async(
     "Concurrent Read",
     iterations: pressure,
     perform: {
      await withTaskGroup(of: Void.self) { group in
       for _ in concurrentIterations {
        group.addTask { blackHole(concurrentCount) }
       }
       await group.waitForAll()
      }
     }
    )

    Measure.Async(
     "Concurrent Write",
     iterations: pressure,
     perform: {
      await withTaskGroup(of: Void.self) { group in
       for _ in concurrentIterations {
        group.addTask { blackHole(concurrentCount += 1) }
       }
       await group.waitForAll()
      }
     }
    )
   }

   Test("Operational") {
    let limit = min(13, pressure.rawValue)
    TestTasks()
    TestMapAsyncDetachedTasks(
     count: $asyncMapCount,
     limit: limit
    )

    Identity(asyncMapCount) == Int(pow(Double(limit), 4))
    Perform.Async { asyncMapCount = .zero }
   }

   Test("Contextual") {
    TestContext()
    TestAsyncContext(pressure: pressure)
   }
  }
 }

 func onCompletion() async {
  print()
  notify(
   String.newline + contextInfo().joined(separator: ",\n"),
   for: "context",
   with: .info
  )
  #if os(WASI) || canImport(SwiftUI)
  // clear previous states / contexts
  Reflection.shared.states.removeAll()
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

nonisolated(unsafe) let notify = Configuration.default

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

 static func / (lhs: Self, rhs: Self) -> Self {
  Self(rawValue: lhs.rawValue / rhs.rawValue)
 }
}

#if os(Linux)
// MARK: - Exports
// Some versions of swift don't recognize exports from other modules using the
// compiler macro `#if canImport(Framework)`
// or it really depends on how the cache is built on macOS and Linux as well.
// Any feedback or information on this would be helpful.
public struct Echo: Function, @unchecked Sendable {
 public let items: [String]
 public let color: Chalk.Color?
 public let background: Chalk.Color?
 public let style: Chalk.Style?
 public let separator: String
 public let terminator: String
 public var detached: Bool = true
 public
 init(
  _ items: Any...,
  color: Chalk.Color? = nil,
  background: Chalk.Color? = nil,
  style: Chalk.Style? = nil,
  separator: String = " ", terminator: String = "\n"
 ) {
  self.items = items.map(String.init(describing:))
  self.color = color
  self.background = background
  self.style = style
  self.separator = separator
  self.terminator = terminator
 }

 public func callAsFunction() {
  echo(
   items as [Any],
   color: color, background: background, style: style,
   separator: separator,
   terminator: terminator
  )
 }
}

/// A test that calls `static func main()` with command and context support
public protocol TestsCommand: Tests & AsyncCommand {}
public extension TestsCommand {
 mutating func main() async throws {
  do { try await callAsTestFromContext() }
  catch {
   exit(Int32(error._code))
  }
 }
}
#endif
