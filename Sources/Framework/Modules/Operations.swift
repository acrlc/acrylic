import Collections
import Extensions

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
 public nonisolated var isEmpty: Bool { queue.keys.isEmpty }

 public typealias DefaultTask = AsyncTask<Sendable, any Error>
 public typealias Running = Deque<(Int, any Operational)>
 public typealias Detached = Deque<(Int, any Operational)>

 @_spi(ModuleReflection)
 nonisolated
 public lazy var queue: Queue = .empty
 @_spi(ModuleReflection)
 nonisolated
 public lazy var running: Running = .empty
 @_spi(ModuleReflection)
 nonisolated
 public lazy var detached: Detached = .empty

 @_spi(ModuleReflection)
 nonisolated
 public subscript(queue key: Int) -> DefaultTask? {
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
  queue.empty()
 }

 public func invalidate() async {
  await Tasks.run { @Sendable in
   while running.notEmpty {
    running.popLast()?.1.cancel()
   }
   while detached.notEmpty {
    detached.popLast()?.1.cancel()
   }
   queue.empty()
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
  await Tasks.run { @Sendable in
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
  let (keys, tasks) = (queue.keys, queue.values)
  for index in keys.indices {
   let (key, task) = (keys[index], tasks[index])

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

 @_spi(ModuleReflection)
 @discardableResult
 public static func detached<T: Sendable>(
  resultType: T.Type = T.self,
  body: @Tasks @escaping () throws -> T,
  onResult: @escaping (T) -> (),
  onError: @escaping (any Error) -> ()
 ) -> Task<(), Never> {
  Task { @Tasks in
   do {
    try onResult(body())
   } catch {
    onError(error)
   }
  }
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func detached<T: Sendable>(
  resultType: T.Type = T.self,
  body: @Tasks @escaping () throws -> T,
  onResult: @escaping (T) -> ()
 ) -> Task<(), any Error> {
  Task { @Tasks in
   try onResult(body())
  }
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func detached<T: Sendable>(
  resultType: T.Type = T.self,
  body: @Tasks @escaping () throws -> T,
  onError: @escaping (any Error) -> ()
 ) -> Task<T?, Never> {
  Task { @Tasks in
   do {
    return try body()
   } catch {
    onError(error)
   }
   return nil
  }
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func detached<T: Sendable>(
  resultType: T.Type = T.self,
  body: @Tasks @escaping () async throws -> T
 ) -> Task<T, any Error> {
  Task { @Tasks in try await body() }
 }
}

extension Tasks: Collection {
 public nonisolated subscript(position: Int) -> (key: Int, value: DefaultTask) {
  (queue.keys[position], queue.values[position])
 }

 public nonisolated
 subscript(bounds: Range<Int>) -> [(key: Int, value: DefaultTask)].SubSequence {
  let (keys, tasks) = (queue.keys, queue.values)
  return keys.indices.map { (keys[$0], tasks[$0]) }[bounds]
 }

 public nonisolated var count: Int { queue.count }

 public nonisolated var indices: Range<Int> { queue.keys.indices }
 public nonisolated func index(after i: Int) -> Int {
  queue.keys.index(after: i)
 }

 public nonisolated var startIndex: Int { queue.keys.startIndex }
 public nonisolated var endIndex: Int { queue.keys.endIndex }

 public nonisolated func makeIterator() -> Iterator { Iterator(tasks: self) }
 public struct Iterator: IteratorProtocol {
  unowned let tasks: Tasks
  var position: Int = .zero

  public mutating func next() -> (key: Int, value: DefaultTask)? {
   if position < tasks.queue.keys.endIndex {
    defer { position += 1 }
    return (tasks.queue.keys[position], tasks.queue.values[position])
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
   if position < tasks.queue.keys.endIndex {
    defer { position += 1 }

    let (key, task) = (tasks.queue.keys[position], tasks.queue.values[position])

    if task.detached {
     tasks.detached.append(
      (key, Task.detached(priority: task.priority, operation: task.perform))
     )
    } else {
     let task = Task(priority: task.priority, operation: task.perform)
     tasks.running.append((key, task))

     try await task.wait()
    }
    return (key, task)
   }
   return nil
  }
 }
}

// MARK: - Tasks Queue
public extension Tasks {
 struct Queue: @unchecked Sendable {
  var _keys: [Int] = .empty
  var _keysOffset: Int = .zero
  var _offsets: [Int] = .empty
  var _values: [DefaultTask] = .empty
  var _valuesOffset: Int = .zero

  public init() {}

  // MARK: Subscript Operations
  @inline(__always)
  public subscript(unchecked key: Int) -> DefaultTask {
   get {
    _values[uncheckedOffset(for: key)]
   }
   set {
    updateValue(newValue, for: key)
   }
  }

  @inline(__always)
  public subscript(key: Int) -> DefaultTask? {
   get {
    guard !_keys.isEmpty else { return nil }
    var offset = 0
    while offset < _keysOffset {
     guard _keys[offset] == key else {
      offset += 1
      continue
     }
     return _values[offset]
    }
    return nil
   }
   set {
    guard let newValue else { return }
    guard contains(key) else {
     store(newValue, for: key)
     return
    }
    updateValue(newValue, for: key)
   }
  }

  // MARK: Key Operations
  @inline(__always)
  @discardableResult
  public mutating func store(_ value: DefaultTask, for key: Int) -> Int {
   let oldOffset = _valuesOffset
   let newOffset = oldOffset + 1
   let keysOffset = _keysOffset
   let newKeysOffset = keysOffset + 1
   _values.append(value)
   _valuesOffset = newOffset
   _keys.append(key)
   _keysOffset = newKeysOffset
   _offsets.append(oldOffset)
   return keysOffset
  }

  @inline(__always)
  public mutating func updateValue(_ newValue: DefaultTask, for key: Int) {
   _values[uncheckedOffset(for: key)] = newValue
  }

  @inline(__always)
  public mutating func removeValue(for key: Int) {
   guard !_keys.isEmpty else { return }
   var offset = 0
   while offset < _keysOffset {
    guard _keys[offset] == key else {
     offset += 1
     continue
    }
    _keys.remove(at: offset)
    _keysOffset -= 1
    _offsets.remove(at: offset)
    _values.remove(at: offset)
    _valuesOffset -= 1
    return
   }
  }

  @inline(__always)
  public func contains(_ key: Int) -> Bool {
   guard !_keys.isEmpty else { return false }
   var offset = 0
   while offset < _keysOffset {
    guard _keys[offset] == key else {
     offset += 1
     continue
    }
    return true
   }
   return false
  }

  @inline(__always)
  func uncheckedOffset(for key: Int) -> Int {
   var offset = 0
   while offset < _keysOffset {
    guard _keys[offset] == key else {
     offset += 1
     continue
    }
    return _offsets[offset]
   }
   fatalError("No value was stored for key: '\(key)'")
  }
 }
}

// MARK: Unkeyed Operations
public extension Tasks.Queue {
 // MARK: Sequence Properties
 static var empty: Self { Self() }
 @inline(__always)
 var isEmpty: Bool {
  _valuesOffset == .zero
 }

 @inline(__always)
 var notEmpty: Bool {
  _valuesOffset > .zero
 }

 var keys: [Int] { _keys }
 var values: [Tasks.DefaultTask] { _values }
 var count: Int { _valuesOffset }

 // MARK: Sequence Operations
 @inline(__always)
 func uncheckedValue(at offset: Int) -> Tasks.DefaultTask {
  _values[offset]
 }

 @inline(__always)
 mutating func updateValue(_ newValue: Tasks.DefaultTask, at offset: Int) {
  _values[offset] = newValue
 }

 mutating func removeValue(at offset: Int) {
  _keys.remove(at: offset)
  _keysOffset -= 1
  _offsets.remove(at: offset)
  _values.remove(at: offset)
  _valuesOffset -= 1
 }

 @inline(__always)
 mutating func empty() {
  _keys = .empty
  _keysOffset = .zero
  _values = .empty
  _valuesOffset = .zero
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
extension Deque: ExpressibleAsEmpty {
 public static var empty: Self { Self() }
 @inline(__always)
 public var notEmpty: Bool { !isEmpty }
}

// MARK: Helper Functions
@_spi(ModuleReflection)
@inline(__always)
public func _isValidResult(_ self: Any) -> Bool {
 !(
  self is () || self is [()] || self is [[()]] ||
   self is ()? || self is [()]? || self is [[()]]?
 )
}

@_spi(ModuleReflection)
@inline(__always)
public func _getValidResults(_ self: [Sendable]) -> [Sendable] {
 self.compactMap { result in
  if let array = result as? [Sendable] {
   _getValidResults(array)
  } else {
   _isValidResult(result) ? result : nil
  }
 }
}
