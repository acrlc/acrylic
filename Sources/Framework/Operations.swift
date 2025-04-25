import Extensions

public protocol AsyncOperator: Actor {
 associatedtype DefaultTask: AsyncOperation
}

public protocol AsyncOperation: Sendable, Detachable {
 associatedtype Output
 associatedtype Failure: Error
 var priority: TaskPriority? { get set }
 var detached: Bool { get set }
 var perform: @Sendable () async throws -> Output { get }
}

/// The endpoint for operations controlled by a module
public struct AsyncTask
<Output, Failure: Error>: AsyncOperation, @unchecked Sendable {
 public var priority: TaskPriority?
 public var detached: Bool
 public let perform: @Sendable () async throws -> Output

 public init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  task: @escaping @Sendable () async throws -> Output
 ) {
  self.priority = priority
  self.detached = detached
  perform = task
 }

 public init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  task: @escaping @Sendable () async -> Output
 ) where Output == Void, Failure == Never {
  self.priority = priority
  self.detached = detached
  perform = task
 }

 public static func detached(
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  task: @escaping @Sendable () async throws -> Output
 ) -> AsyncTask<Output, Failure> {
  AsyncTask<Output, Failure>(
   priority: priority, detached: detached, task: task
  )
 }
 
// public static func detached(
//  priority: TaskPriority? = nil,
//  _ detached: Bool = true,
//  task: @Sendable @escaping () async throws -> Any
// ) -> AsyncTask<Any, Failure> {
//  AsyncTask<Any, Failure>(
//   priority: priority, detached: detached, task: task
//  )
// }

 public static func detached(
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  task: @escaping @Sendable () async -> Output
 ) -> AsyncTask<Output, Failure> where Failure == Never {
  AsyncTask<Output, Failure>(
   priority: priority, detached: detached, task: task
  )
 }

 @_transparent
 public func callAsFunction() async throws -> Output {
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

 public typealias DefaultTask = AsyncTask<Any, any Error>
 public typealias Running = KeyValueStorage<any Operational>
 public typealias Detached = KeyValueStorage<any Operational>

 @_spi(ModuleReflection)
 @preconcurrency public nonisolated(unsafe) var queue: Queue = .empty
 @_spi(ModuleReflection)
 @preconcurrency public nonisolated(unsafe) var running: Running = .empty
 @_spi(ModuleReflection)
 @preconcurrency public nonisolated(unsafe) var detached: Detached = .empty

 @_spi(ModuleReflection)
 public nonisolated
 subscript(queue key: Int) -> DefaultTask {
  get { queue[unchecked: key] }
  set { queue[key] = newValue }
 }

 public nonisolated
 subscript<A: Hashable>(queue key: A) -> DefaultTask {
  get { queue[unchecked: key.hashValue] }
  set { queue[key.hashValue] = newValue }
 }
 
 public nonisolated
 subscript<A: Hashable>(queue key: A) -> DefaultTask? {
  get { queue[key.hashValue] }
  set { queue[key.hashValue] = newValue }
 }

 @_spi(ModuleReflection)
 public subscript(running key: Int) -> (any Operational) {
  running[unchecked: key]
 }
 
 @_spi(ModuleReflection)
 public subscript(checkedRunning key: Int) -> (any Operational)? {
  running[key]
 }
 
 public nonisolated
 subscript<A: Hashable>(running key: A) -> (any Operational)? {
  get { running[key.hashValue] }
  set { running[key.hashValue] = newValue }
 }

 @_spi(ModuleReflection)
 public subscript(detached key: Int) -> (any Operational) {
  detached[unchecked: key]
 }

 public nonisolated
 subscript<A: Hashable>(detached key: A) -> (any Operational)? {
  get { detached[key.hashValue] }
  set { detached[key.hashValue] = newValue }
 }

 public nonisolated var isCancelled: Bool {
  running.values.allSatisfy(\.isCancelled) &&
   detached.values.allSatisfy(\.isCancelled)
 }

 public nonisolated func invalidate() {
  while running.notEmpty {
   running.popLast()?.cancel()
  }
  while detached.notEmpty {
   detached.popLast()?.cancel()
  }
  queue.empty()
 }

 public func invalidate() async {
  await Tasks.run { @Sendable in
   while running.notEmpty {
    running.popLast()?.cancel()
   }
   while detached.notEmpty {
    detached.popLast()?.cancel()
   }
   queue.empty()
  }
 }

 /// Cancels all (detached and synchronous) tasks
 public nonisolated func cancel() {
  while running.notEmpty {
   running.popLast()?.cancel()
  }
  while detached.notEmpty {
   detached.popLast()?.cancel()
  }
 }

 public func cancel() async {
  await Tasks.run { @Sendable in
   while running.notEmpty {
    running.popLast()?.cancel()
   }
   while detached.notEmpty {
    detached.popLast()?.cancel()
   }
  }
 }

 public nonisolated func cancel<A: Hashable>(_ key: A) {
  let _key = key.hashValue
  if let task = running[_key] {
   task.cancel()
   running.removeValue(for: _key)
  } else if let task = detached[_key] {
   task.cancel()
   detached.removeValue(for: _key)
  }
 }

 public func cancel<A: Hashable>(_ key: A) async {
  await Tasks.run { @Sendable in
   let _key = key.hashValue
   if let task = running[_key] {
    task.cancel()
    running.removeValue(for: _key)
   } else if let task = detached[_key] {
    task.cancel()
    detached.removeValue(for: _key)
   }
  }
 }

 public nonisolated func wait() async throws {
  for task in running.values {
   try await task.wait()
  }
 }

 public nonisolated func waitForDetached() async throws {
  for task in detached.values {
   try await task.wait()
  }
 }

 public nonisolated func waitForAll() async throws {
  for task in running.values {
   try await task.wait()
  }
  for task in detached.values {
   try await task.wait()
  }
 }

 @discardableResult
 public nonisolated func next() async throws -> Sendable? {
  try await running.popFirst()?.wait()
 }

 @discardableResult
 public nonisolated func last() async throws -> Sendable? {
  try await running.popLast()?.wait()
 }

 @discardableResult
 public nonisolated func nextDetached() async throws -> Sendable? {
  try await detached.popFirst()?.wait()
 }

 @discardableResult
 public nonisolated func lastDetached() async throws -> Sendable? {
  try await detached.popLast()?.wait()
 }

 public func callAsFunction() async throws {
  let (keys, tasks) = (queue.keys, queue.values)
  for index in keys.indices {
   let (key, task) = (keys[index], tasks[index])

   if task.detached {
    detached.store(
     Task.detached(priority: task.priority, operation: task.perform), for: key
    )
   } else {
    let task = Task.detached(priority: task.priority, operation: task.perform)
    running.store(task, for: key)

    try await task.wait()
   }
  }
 }

 public func callAsFunction<A: Hashable>(_ key: A) async throws {
  let _key = key.hashValue
  guard let offset = queue.offset(for: _key) else {
   fatalError("No task with key \(key) was found in queue.")
  }
  let task = queue.values[offset]
  if task.detached {
   detached.store(
    Task.detached(priority: task.priority, operation: task.perform), for: _key
   )
  } else {
   let task = Task.detached(priority: task.priority, operation: task.perform)
   running.store(task, for: _key)

   try await task.wait()
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
  resultType _: T.Type = T.self, body: @Tasks () throws -> T
 ) async rethrows -> T {
  try body()
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func detached<T: Sendable>(
  priority: TaskPriority? = nil,
  resultType _: T.Type = T.self,
  body: @Tasks @escaping () throws -> T,
  onResult: @escaping (T) -> Void,
  onError: @escaping (any Error) -> Void
 ) -> Task<Void, Never> {
  Task.detached(priority: priority) { @Tasks in
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
  priority: TaskPriority? = nil,
  resultType _: T.Type = T.self,
  body: @Tasks @escaping () throws -> T,
  onResult: @escaping (T) -> Void
 ) -> Task<Void, any Error> {
  Task.detached(priority: priority) { @Tasks in
   try onResult(body())
  }
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func detached<T: Sendable>(
  priority: TaskPriority? = nil,
  resultType _: T.Type = T.self,
  body: @Tasks @escaping () throws -> T,
  onError: @escaping (any Error) -> Void
 ) -> Task<T?, Never> {
  Task.detached(priority: priority) { @Tasks in
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
  priority: TaskPriority? = nil,
  resultType _: T.Type = T.self,
  body: @Tasks @escaping () async throws -> T
 ) -> Task<T, any Error> {
  Task.detached(priority: priority) { @Tasks in try await body() }
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
     tasks.detached.store(
      Task.detached(priority: task.priority, operation: task.perform), for: key
     )
    } else {
     let task = Task.detached(priority: task.priority, operation: task.perform)
     tasks.running.store(task, for: key)

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

  @inline(__always)
  func offset(for key: Int) -> Int? {
   var offset = 0
   while offset < _keysOffset {
    guard _keys[offset] == key else {
     offset += 1
     continue
    }
    return _offsets[offset]
   }
   return nil
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
