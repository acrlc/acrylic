@_spi(ModuleReflection) import Acrylic
@_exported import Benchmarks
@_exported import Time
import Utilities

/// A module that benchmarks functions
extension Benchmarks:
 TestProtocol,
 @retroactive Identifiable,
 @unchecked @retroactive Sendable {
 public func callAsTest() async throws {
  do {
   let results = try await self()
   for offset in results.keys.sorted() {
    let result = results[offset]!
    let title = result.id ?? "Benchmark " + (offset + 1).description
    let size = result.size
    let single = size == 1
    let time = single ? result.times[0] : result.average

    print(
     "[ " + title.applying(color: .cyan, style: .bold) + " ]",
     "\("called \(size) \(single ? "time" : "times")", style: .boldDim)",
     "\(single ? "in" : "average", color: .cyan, style: .bold)" + .space +
      "\(time.description + .space, style: .boldDim)"
    )

    let results = _getValidResults(result.results)

    if results.notEmpty {
     print(
      String.space,
      "\("return", style: .boldDim)",
      "\("\(results[0])".readableRemovingQuotes, style: .bold)"
     )
    }
   }
  } catch {
   throw error
  }
 }

 init(
  id: ID,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  benchmarks: @escaping () -> [any BenchmarkProtocol]
 ) {
  self.init()
  self.id = id
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  setup = setUp
  complete = onCompletion
  cleanup = cleanUp
  items = benchmarks
 }

 init(
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  benchmarks: @escaping () -> [any BenchmarkProtocol]
 ) where ID == EmptyID {
  self.init()
  sourceLocation = SourceLocation(
   fileID: fileID,
   line: line,
   column: column
  )
  setup = setUp
  complete = onCompletion
  cleanup = cleanUp
  items = benchmarks
 }

 public typealias Modules = BenchmarkModules<ID>
}

/// A module that benchmarks other modules
public struct BenchmarkModules<ID: Hashable>: TestProtocol {
 let benchmarks: Benchmarks<ID>
 public var id: ID? { benchmarks.id }
 public init(
  _ id: ID,
  warmup: Size = .zero,
  iterations: Size = 10,
  timeout: Double = 5.0,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular modules: @escaping () -> Modules
 ) {
  benchmarks = .init(
   id: id,
   fileID: fileID,
   line: line,
   column: column,
   setUp: setUp,
   onCompletion: onCompletion,
   cleanUp: cleanUp,
   benchmarks: {
    return modules().map { module -> any BenchmarkProtocol in
     let id = module.idString
     if let task = module as? any AsyncFunction {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: task.callAsFunction
      )
     } else if let task = module as? any Function {
      return Measure(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: task.callAsFunction
      )
     } else if var test = module as? (any TestProtocol) {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: { try await test.callAsTest() }
      )
     } else {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: { try await (module.void as! Modules).callAsFunction() }
      )
     }
    }
   }
  )
 }

 public init(
  warmup: Size = .zero,
  iterations: Size = 10,
  timeout: Double = 5.0,
  fileID: String = #fileID,
  line: Int = #line,
  column: Int = #column,
  setUp: (() async throws -> ())? = nil,
  onCompletion: (() async throws -> ())? = nil,
  cleanUp: (() async throws -> ())? = nil,
  @Modular modules: @escaping () -> Modules
 ) where ID == EmptyID {
  benchmarks = Benchmarks(
   fileID: fileID,
   line: line,
   column: column,
   setUp: setUp,
   onCompletion: onCompletion,
   cleanUp: cleanUp,
   benchmarks: {
    return modules().map { module -> any BenchmarkProtocol in
     let id = module.idString
     if let task = module as? any AsyncFunction {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: task.callAsFunction
      )
     } else if let task = module as? any Function {
      return Measure(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: task.callAsFunction
      )
     } else if var test = module as? (any TestProtocol) {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: { try await test.callAsTest() }
      )
     } else {
      return Measure.Async(
       id, warmup: warmup, iterations: iterations, timeout: timeout,
       perform: { try await (module.void as! Modules).callAsFunction() }
      )
     }
    }
   }
  )
 }

 public func callAsTest() async throws {
  try await benchmarks.callAsTest()
 }
}

public extension TestProtocol {
 typealias Benchmark<A> = Benchmarks<A> where A: Hashable
 typealias BenchmarkModule<A> = BenchmarkModules<A> where A: Hashable
}
