import Collections
import Extensions
import OrderedCollections

public protocol AsyncOperator: Actor {
 associatedtype DefaultTask: AsyncOperation
}

public protocol AsyncOperation: Sendable, Detachable {
 associatedtype Output: Sendable
 associatedtype Failure: Error
 var priority: TaskPriority? { get set }
 var detached: Bool { get set }
 var perform: @Sendable () async throws -> Output? { get }
}

/// The endpoint for operations controlled by a module
public struct AsyncTask
<Output: Sendable, Failure: Error>: AsyncOperation, @unchecked Sendable {
 public var priority: TaskPriority?
 public var detached: Bool
 public let perform: @Sendable () async throws -> Output?

 public init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  task: @Sendable @escaping () async throws -> Output?
 ) {
  self.priority = priority
  self.detached = detached
  perform = task
 }

 public init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  task: @Sendable @escaping () async -> Output?
 ) where Failure == Never {
  self.priority = priority
  self.detached = detached
  perform = task
 }

 public static func detached(
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  task: @Sendable @escaping () async throws -> Output
 ) -> AsyncTask<Output, Failure> {
  AsyncTask<Output, Failure>(
   priority: priority, detached: detached, task: task
  )
 }
 
 public static func detached(
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  task: @Sendable @escaping () async -> Output
 ) -> AsyncTask<Output, Failure> where Failure == Never {
  AsyncTask<Output, Failure>(
   priority: priority, detached: detached, task: task
  )
 }

 @_transparent
 public func callAsFunction() async throws -> Output? {
  try await perform()
 }
}

/// A global actor, responsible for ensuring the safe execution and delivery of
/// tasks
@globalActor
public actor Tasks:
 @unchecked Sendable, AsyncOperator, Operational, ExpressibleAsEmpty {
 public static let shared = Tasks()
 public nonisolated static var empty: Self { Self() }

 public typealias DefaultTask = AsyncTask<Sendable, any Error>
 public typealias Queue = OrderedDictionary<Int, DefaultTask>
 public typealias Running = Deque<(Int, any Operational)>
 public typealias Detached = Deque<(Int, any Operational)>

 @_spi(ModuleReflection)
 public nonisolated(unsafe) var queue: Queue = .empty
 @_spi(ModuleReflection)
 public nonisolated(unsafe) var running: Running = .empty
 @_spi(ModuleReflection)
 public nonisolated(unsafe) var detached: Detached = .empty

 @_spi(ModuleReflection)
 public nonisolated(unsafe) subscript(queue key: Int) -> DefaultTask? {
  get { queue[key] }
  set { queue[key] = newValue }
 }

 @_spi(ModuleReflection)
 public subscript(running key: Int) -> (any Operational)? {
  running.first(where: { $0.0 == key })?.1
 }

 @_spi(ModuleReflection)
 public subscript(detached key: Int) -> (any Operational)? {
  detached.first(where: { $0.0 == key })?.1
 }

 public nonisolated var isCancelled: Bool {
  running.allSatisfy(\.1.isCancelled) &&
   detached.allSatisfy(\.1.isCancelled)
 }

 public nonisolated func invalidate() {
  while running.notEmpty {
   running.popLast()?.1.cancel()
  }
  while detached.notEmpty {
   detached.popLast()?.1.cancel()
  }
  queue = .empty
 }

 public func invalidate() async {
  await Tasks.run {
   while running.notEmpty {
    running.popLast()?.1.cancel()
   }
   while detached.notEmpty {
    detached.popLast()?.1.cancel()
   }
   queue = .empty
  }
 }

 /// Cancels all (detached and synchronous) tasks
 public nonisolated func cancel() {
  while running.notEmpty {
   running.popLast()?.1.cancel()
  }
  while detached.notEmpty {
   detached.popLast()?.1.cancel()
  }
 }

 public func cancel() async {
  await Tasks.run {
   while running.notEmpty {
    running.popLast()?.1.cancel()
   }
   while detached.notEmpty {
    detached.popLast()?.1.cancel()
   }
  }
 }
 
 public nonisolated func wait() async throws {
  for (_, task) in running {
   try await task.wait()
  }
 }

 public nonisolated func waitForDetached() async throws {
  for (_, task) in detached {
   try await task.wait()
  }
 }

 public nonisolated func waitForAll() async throws {
  for (_, task) in running {
   try await task.wait()
  }
  for (_, task) in detached {
   try await task.wait()
  }
 }
  
 @discardableResult
 public nonisolated func next() async throws -> Sendable? {
  try await running.popFirst()?.1.wait()
 }
 
 @discardableResult
 public nonisolated func last() async throws -> Sendable? {
  try await running.popLast()?.1.wait()
 }
 
 @discardableResult
 public nonisolated func nextDetached() async throws -> Sendable? {
  try await detached.popFirst()?.1.wait()
 }
 
 @discardableResult
 public nonisolated func lastDetached() async throws -> Sendable? {
  try await detached.popLast()?.1.wait()
 }
 
 public func callAsFunction() async throws {
  for (key, task) in queue {
   if task.detached {
    detached.append(
     (key, Task.detached(priority: task.priority, operation: task.perform))
    )
   } else {
    let task = Task(priority: task.priority, operation: task.perform)
    running.append((key, task))

    try await task.wait()
   }
  }
 }

 public init() {}
 deinit { self.cancel() }

 public static func assumeIsolated<T>(
  _ operation: @escaping () throws -> T,
  file: StaticString = #fileID,
  line: UInt = #line
 ) rethrows -> T {
  try Tasks.shared.assumeIsolated(
   { _ in try operation() },
   file: file,
   line: line
  )
 }

 @Tasks
 static func run<T: Sendable>(
  resultType: T.Type = T.self, body: @Tasks () throws -> T
 ) async rethrows -> T {
  try body()
 }
}

extension Tasks: Collection {
 public nonisolated subscript(position: Int) -> (key: Int, value: DefaultTask) {
  queue.elements[position]
 }

 public nonisolated subscript(bounds: Range<Int>) -> Queue.Elements
  .SubSequence {
  queue.elements[bounds]
 }

 public nonisolated var count: Int { queue.count }
 
 public nonisolated var indices: Range<Int> { queue.elements.indices }
 public nonisolated func index(after i: Int) -> Int {
  queue.elements.index(after: i)
 }

 public nonisolated var startIndex: Int { queue.elements.startIndex }
 public nonisolated var endIndex: Int { queue.elements.endIndex }

 public nonisolated func makeIterator() -> Iterator { Iterator(tasks: self) }
 public struct Iterator: IteratorProtocol {
  unowned let tasks: Tasks
  var position: Int = .zero

  public mutating func next() -> (key: Int, value: DefaultTask)? {
   if position < tasks.queue.elements.endIndex {
    defer { position += 1 }
    return tasks.queue.elements[position]
   }
   return nil
  }
 }
}

extension Tasks: AsyncSequence {
 public nonisolated func makeAsyncIterator() -> AsyncIterator {
  AsyncIterator(tasks: self)
 }

 public struct AsyncIterator: AsyncIteratorProtocol {
  unowned let tasks: Tasks
  var position: Int = .zero

  /// Performs and returns the (key, task) for processing
  public mutating func next() async throws -> (key: Int, value: DefaultTask)? {
   if position < tasks.queue.elements.endIndex {
    defer { position += 1 }

    let element = tasks.queue.elements[position]
    let key = element.key
    let task = element.value

    if task.detached {
     tasks.detached.append(
      (key, Task.detached(priority: task.priority, operation: task.perform))
     )
    } else {
     let task = Task(priority: task.priority, operation: task.perform)
     tasks.running.append((key, task))

     try await task.wait()
    }
    return element
   }
   return nil
  }
 }
}

// MARK: - Protocols
public protocol Operational {
 associatedtype Success: Sendable
 var isCancelled: Bool { get }
 @inlinable
 func cancel()
 @discardableResult
 func wait() async throws -> Success
}

public extension Operational {
 @inline(__always)
 var isRunning: Bool { !isCancelled }

 @inline(__always)
 func cancelIfNeeded() {
  guard !isCancelled else {
   return
  }
  cancel()
 }
}

extension Task: Operational {
 @_disfavoredOverload
 @discardableResult
 public func wait() async throws -> Success {
  try await value
 }
}

public extension Task where Failure == Never {
 @discardableResult
 func wait() async -> Success {
  await value
 }
}

// MARK: Helper Extensions
@_spi(ModuleReflection)
public extension Sendable {
 var _isValid: Bool {
  !(
   self is () || self is [()] || self is [[()]] ||
    self is ()? || self is [()]? || self is [[()]]?
  )
 }
}

@_spi(ModuleReflection)
public extension [Sendable] {
 var _validResults: Self {
  compactMap { result in
   if let array = result as? Self {
    array._validResults
   } else {
    result._isValid ? result : nil
   }
  }
 }
}

@_spi(ModuleReflection)
public extension [Any] {
 var _validResults: Self {
  func _isValid(_ self: Any) -> Bool {
   !(
    self is () || self is [()] || self is [[()]] ||
     self is ()? || self is [()]? || self is [[()]]?
   )
  }

  return compactMap { result in
   if let array = result as? Self {
    array._validResults
   } else {
    _isValid(result) ? result : nil
   }
  }
 }
}

extension OrderedDictionary: ExpressibleAsEmpty {
 public static var empty: Self { Self() }
 @inline(__always)
 public var notEmpty: Bool { !isEmpty }
}

extension Deque: ExpressibleAsEmpty {
 public static var empty: Self { Self() }
 @inline(__always)
 public var notEmpty: Bool { !isEmpty }
}
