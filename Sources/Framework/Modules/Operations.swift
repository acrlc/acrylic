public protocol AsyncOperation: Sendable {
 associatedtype Output: Sendable
 associatedtype Failure: Error
 var id: Int { get }
 var priority: TaskPriority? { get }
 var detached: Bool { get }
 @inlinable
 @discardableResult
 func callAsFunction() async throws -> Output?
}

/// The endpoint for operations controlled by a module
public struct AsyncTask
<Output: Sendable, Failure: Error>: AsyncOperation, @unchecked Sendable {
 public var id: Int
 public var priority: TaskPriority?
 public var detached: Bool
 public var perform: () async throws -> Output?

 @_spi(ModuleReflection)
 public init(
  id: Int,
  priority: TaskPriority? = nil,
  detached: Bool = false,
  task: @Sendable @escaping () async throws -> Output?
 ) {
  self.id = id
  self.priority = priority
  self.detached = detached
  perform = task
 }

 @_spi(ModuleReflection)
 public func callAsFunction() async throws -> Output? {
  try await perform()
 }
}

@Reflection
/// Manages tasks for a reflection to allow concurrent tasks
/// that can pause or cancel when needed
open class Tasks: @unchecked Sendable, Operational {
 public static let shared = Tasks()
 public typealias DefaultTask = any AsyncOperation
 public typealias Queue = [(Int, DefaultTask)]
 public typealias Running = [(Int, any Operational)]
 public typealias Detached = [(Int, any Operational)]

 @_spi(ModuleReflection)
 public nonisolated(unsafe) var queue: Queue = .empty
 @_spi(ModuleReflection)
 public nonisolated(unsafe) var running: Running = .empty
 @_spi(ModuleReflection)
 public nonisolated(unsafe) var detached: Detached = .empty

 public subscript<A: AsyncOperation>(queue key: Int) -> A? {
  get { queue[key] as? A }
  set {
   queue += [(key, newValue!)]
  }
 }

 public nonisolated var isCancelled: Bool {
  running.map(\.1).allSatisfy(\.isCancelled)
 }

 public func invalidate() {
  while running.notEmpty {
   let task = running.removeLast().1
   task.cancel()
  }
  queue.removeAll()
  detached.removeAll()
 }

 public func invalidate() async {
  await running.queue { _, task in
   task.cancel()
  }
  await withTaskGroup(of: Void.self) { group in
   group.addTask { self.running.removeAll() }
   group.addTask { self.queue.removeAll() }
   group.addTask { self.detached.removeAll() }
   await group.waitForAll()
  }
 }

 public nonisolated func cancel() {
  while running.notEmpty {
   let task = running.removeLast().1
   task.cancel()
  }
  detached.removeAll()
 }

 /// Cancel detached and synchronous tasks
 public func cancel() async {
  await running.queue { _, task in
   task.cancel()
  }
  await withTaskGroup(of: Void.self) { group in
   group.addTask { self.running.removeAll() }
   group.addTask { self.detached.removeAll() }
   await group.waitForAll()
  }
 }

 public func wait() async throws {
  for task in running.map(\.1) {
   try await task.wait()
  }
  for (_, task) in detached {
   try await task.wait()
  }
 }

 @_spi(ModuleReflection)
 public func callAsFunction() async throws {
  let current = queue.map(\.1)

  for task in current {
   let key = task.id
   if task.detached {
    let task = Task.detached(priority: task.priority) { try await task() }

    detached[key] = task
    running[key] = task
   } else {
    let task = Task(priority: task.priority) { try await task() }

    running[key] = task
    try await task.wait()
   }
  }
 }

 public nonisolated(unsafe) init() {}
 deinit { self.cancel() }
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

// MARK: Helper Extensions
@_spi(ModuleReflection)
public extension [(Int, any Operational)] {
 mutating func removeValue(forKey key: Int) {
  if let index = firstIndex(where: { $0.0 == key }) {
   remove(at: index)
  }
 }

 subscript(_ key: Int) -> (any Operational)? {
  get { first(where: { $0.0 == key })?.1 }
  set {
   if let newValue {
    if let index = firstIndex(where: { $0.0 == key }) {
     self[index] = newValue
    } else {
     append((key, newValue))
    }
   } else {
    removeAll(where: { $0.0 == key })
   }
  }
 }
}

@_spi(ModuleReflection)
public extension [(Int, any AsyncOperation)] {
 mutating func removeValue(forKey key: Int) {
  if let index = firstIndex(where: { $0.0 == key }) {
   remove(at: index)
  }
 }

 subscript(_ key: Int) -> (any AsyncOperation)? {
  get { first(where: { $0.0 == key })?.1 }
  set {
   if let newValue {
    if let index = firstIndex(where: { $0.0 == key }) {
     self[index] = newValue
    } else {
     append((key, newValue))
    }
   } else {
    removeAll(where: { $0.0 == key })
   }
  }
 }
}

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
