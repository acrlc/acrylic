public protocol Operational {
 @inlinable
 var isRunning: Bool { get }
 @inlinable
 func cancel()
}

extension Operational {
 @inlinable
 func wait() {
  repeat {
   continue
  } while isRunning
 }
}

extension Task: Operational {
 public var isRunning: Bool { !isCancelled }
}

public protocol AsyncOperation: Sendable, Identifiable, Operational {
 associatedtype Output: Sendable
 associatedtype Failure: Error
 var priority: TaskPriority? { get }
 var detached: Bool { get }
 var task: Task<Output?, Failure>? { get }
 var tasks: Tasks? { get set }
 @inlinable
 @discardableResult
 func callAsFunction() async throws -> Output?
}

/// The endpoint for operations controlled by a module
public struct AsyncTask
<Output: Sendable, Failure: Error>: AsyncOperation, @unchecked Sendable {
 public var id: AnyHashable
 public var priority: TaskPriority?
 public let detached: Bool
 public var perform: () async throws -> Output?

 @usableFromInline
 weak var context: ModuleContext?

 public var tasks: Tasks? {
  get {
   guard let context else {
    return nil
   }
   return context.tasks
  }
  nonmutating set {
   guard let context, let newValue else {
    return
   }
   context.tasks = newValue
  }
 }

 @_spi(ModuleReflection)
 @inlinable
 public var task: Task<Output?, Error>? {
  get {
   tasks?.running[id] as? Task<Output?, any Error>
  }
  nonmutating set { self.tasks?.running[self.id] = newValue }
 }

 @_spi(ModuleReflection)
 public init(
  id: AnyHashable,
  priority: TaskPriority? = nil,
  detached: Bool = false,
  context: ModuleContext,
  task: @Sendable @escaping () async throws -> Output?
 ) where Failure == Never {
  self.id = id
  self.priority = priority
  self.detached = detached
  self.context = context
  perform = task
 }

 public var isRunning: Bool {
  guard
   let tasks,
   let id = tasks.running.first(where: { $0.0 == self.id })?.0
  else {
   return false
  }
  return tasks.running[id].unsafelyUnwrapped.isRunning
 }

 /// Removes the task form the operator without cancelling
 public func remove(with context: ModuleContext) {
  context.tasks.running.removeValue(for: id)
  context.tasks.queue.removeValue(for: id)

  if !context.isRunning {
   context.tasks.completed = true
  }
 }

 /// Cancels and removes a task from the operator
 /// Note: Not currently being used for current functionality
 public func cancel() {
  guard let context else {
   return
  }
  let id = id
  if let task = context.tasks.running[id] {
   task.cancel()
   context.tasks.running.removeValue(for: id)
  }
  context.tasks.queue.removeValue(for: id)
 }

 @_spi(ModuleReflection)
 @inlinable
 public func callAsFunction() async throws -> Output? {
  if let context {
   remove(with: context)
  }

  let task =
   detached
    ? Task<Output?, Error>.detached(
     priority: priority,
     operation: { try await perform() }
    )
    :
    Task<Output?, Error>(
     priority: priority,
     operation: { try await perform() }
    )
  self.task = task
  return try await task.value
 }
}

/// Manages tasks for a reflection to allow concurrent tasks
/// that can pause or cancel when needed
public actor Tasks: @unchecked Sendable {
 public static let shared = Tasks()
 @usableFromInline typealias Key = AnyHashable
 public typealias DefaultTask = any AsyncOperation
 public typealias Queue = [(AnyHashable, DefaultTask)]
 public typealias Running = [(AnyHashable, Operational)]

 public init() {}
 public nonisolated lazy var queue: Queue = .empty
 public nonisolated lazy var running: Running = .empty

 @inlinable
 public nonisolated var keyTasks: [Operational] { running.map(\.1) }
 @inlinable
 public nonisolated var operations: [DefaultTask] { queue.map(\.1) }

 public nonisolated var isRunning: Bool {
  guard !completed else {
   return false
  }
  return running.notEmpty || detached.notEmpty
 }

 public func removeAll() {
  queue.removeAll()
  running.removeAll()
  detached.removeAll()
 }

 public nonisolated lazy var cancellationTask: Task<(), Never>? = nil
 public func cancel() async {
  await cancellationTask?.wait()
  cancellationTask = Task {
   for operation in self.keyTasks.reversed() {
    operation.cancel()
   }
  }
 }

 @inlinable
 public func wait() async throws {
  for task in keyTasks.map({ $0 as any Operational }) {
   try await task.wait()
  }
 }

 @inlinable
 public func waitForAll() async throws {
  try await wait()

  for (_, task) in detached {
   try await task.wait()
  }
 }

 @_spi(ModuleReflection)
 public nonisolated lazy var task: Task<[AnyHashable: Sendable], Error>? = nil
 public nonisolated lazy var detached = [AnyHashable: Task<Sendable, Error>]()
 public nonisolated lazy var completed: Bool = false

 @_spi(ModuleReflection)
 @inlinable
 @discardableResult
 public func callAsFunction() async throws -> [AnyHashable: Sendable]? {
  await cancel()

  let current = operations
  removeAll()
  completed = false

  let task = Task<[AnyHashable: Sendable], Error> {
   var results: [AnyHashable: Sendable] = .empty

   for task in current {
    let id = task.id
    let key = AnyHashable(id)

    if task.detached {
     self.detached[key] =
      Task { try await task() }
    }
    else {
     results[key] = try await task()
    }
   }

   return results
  }
  self.task = task
  return try await task.value
 }
}

// MARK: - Helper Extensions
@_spi(ModuleReflection)
public extension [(AnyHashable, any Operational)] {
 mutating func removeValue(for key: AnyHashable) {
  if let index = firstIndex(where: { $0.0 == key }) {
   remove(at: index)
  }
 }

 subscript(_ key: AnyHashable) -> (any Operational)? {
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
public extension [(AnyHashable, any AsyncOperation)] {
 mutating func removeValue(for key: AnyHashable) {
  if let index = firstIndex(where: { $0.0 == key }) {
   remove(at: index)
  }
 }

 subscript(_ key: AnyHashable) -> (any AsyncOperation)? {
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

extension Task {
 @discardableResult
 @usableFromInline
 func wait() async throws -> Success {
  try await value
 }
}

extension Task where Failure == Never {
 @discardableResult
 @usableFromInline
 func wait() async -> Success {
  await value
 }
}

extension AnyHashable: @unchecked Sendable {}
