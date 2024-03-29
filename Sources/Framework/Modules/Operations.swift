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

public protocol AsyncOperation: Identifiable, Operational {
 associatedtype Output: Sendable
 associatedtype Failure: Error
 associatedtype Operator: Tasks
 var priority: TaskPriority? { get }
 var detached: Bool { get }
 var task: Task<Output?, Failure>? { get }
 var `operator`: Operator? { get set }
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

 public var `operator`: Tasks? {
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
  get { self.operator?.running[id] as? Task<Output?, any Error> }
  nonmutating set { self.operator?.running[self.id] = newValue }
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
   let `operator`,
   let id = `operator`.running.first(where: { $0.0 == self.id })?.0
  else {
   return false
  }
  return `operator`.running[id].unsafelyUnwrapped.isRunning
 }

 /// Removes the task form the operator without cancelling
 public func remove(with context: ModuleContext) {
  let id = id
  context.tasks.running[id] = nil
  // context.tasks.queue[id] = nil
 }

 /// Cancels and removes a task from the operator
 /// Note: Not currently being used for current functionality
 public func cancel() {
  guard let context else {
   return
  }
  context.phase.withLockUnchecked {
   let id = id
   if let task = context.tasks.running[id] {
    task.cancel()
    context.tasks.running[id] = nil
   }
   context.tasks.queue[id] = nil
  }
 }

 @_spi(ModuleReflection)
 @inlinable
 public func callAsFunction() async throws -> Output? {
  // defer { if let context { self.remove(with: context) } }
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

import protocol Core.ExpressibleAsEmpty
import struct os.OSAllocatedUnfairLock
/// Manages tasks for a reflection to allow concurrent tasks
/// that can pause or cancel when needed
public final class Tasks: Identifiable, ExpressibleAsEmpty, Equatable {
 public static let shared: Tasks = .empty

 @_spi(ModuleReflection)
 public init(id: AnyHashable? = nil) {
  self.id = id ?? AnyHashable(ObjectIdentifier(self))
 }

 public nonisolated lazy var id: AnyHashable = ObjectIdentifier(self)
 public static func == (lhs: Tasks, rhs: Tasks) -> Bool {
  lhs.id == rhs.id
 }

 public static let empty = Tasks()
 public nonisolated var isEmpty: Bool { self == Tasks.empty }

 @usableFromInline typealias Key = AnyHashable
 public typealias DefaultTask = any AsyncOperation
 public typealias Queue = [(AnyHashable, DefaultTask)]
 public typealias Running = [(AnyHashable, Operational)]

 public var queue: Queue = .empty

 @_spi(ModuleReflection)
 public var running: Running = .empty

 @_spi(ModuleReflection)
 public var keyTasks: [Operational] { self.running.map(\.1) }
 @_spi(ModuleReflection)
 @inlinable
 public var operations: [DefaultTask] { self.queue.map(\.1) }
 public var isRunning: Bool { keyTasks.contains(where: \.isRunning) }

 @usableFromInline
 let phase = OSAllocatedUnfairLock(uncheckedState: ())

 public func cancelCurrent() {}

 public func removeAll() {
  self.phase.withLockUnchecked {
   self.queue.removeAll()
   self.running.removeAll()
  }
 }

 public func cancel() {
  self.task?.cancel()
  for operation in self.keyTasks.reversed() {
   operation.cancel()
  }
 }

// @inlinable func cancelAndWait() {
//  for operation in self.keyTasks.reversed() {
//   operation.cancel()
//   operation.wait()
//  }
//  for operation in self.operations.reversed() {
//   operation.cancel()
//   operation.wait()
//  }
// }

 /// Allows tasks to finish before performing the next block
 @inlinable
 func waitForAll() {
  repeat {
   continue
  } while self.isRunning
 }

// @inlinable func wait() {
//  repeat { continue }
//  while operations.contains(where: { $0.isRunning && !$0.detached })
// }
// @usableFromInline var task: Task<(), Error>?
// @inlinable mutating func callAsFunction() async throws {
//  // defer { self.removeAll() }
//  // self.cancelCurrent()
//  let current = self.operations
//  self.task = Task {
//   try await withThrowingTaskGroup(of: Void.self) { group in
//    var operations = current
//    var detached = [DefaultTask]()
//
//    while operations.notEmpty {
//     let task = operations.removeFirst()
//     let isDetached = task.detached
//     if isDetached {
//      detached.append(task)
//     } else {
//      if detached.notEmpty {
//       for detachedTask in detached { group.addTask { try await detachedTask()
//       } }
//       detached = .empty
//      }
//      try await task()
//     }
//    }
//
//    if detached.notEmpty {
//     for detachedTask in detached { group.addTask { try await detachedTask() }
//     }
//    }
//   }
//  }
//  try await task?.value
// }

 @_spi(ModuleReflection)
 public var task: Task<[Sendable], Error>?

 @_spi(ModuleReflection)
 @inlinable
 @discardableResult
 public func callAsFunction() async throws -> [Sendable]? {
  #if DEBUG
  assert(!self.isRunning)
  #endif
  self.cancel()

  let current = self.operations
  self.removeAll()

  self.task = Task {
   var results: [Sendable] = .empty
   for task in current {
    if task.detached {
     Task { try await task() }
    }
    else {
     try await results.append(task())
    }
   }
   return results
  }

  return try await task?.value
 }
}

// MARK: - Helper Extensions
@_spi(ModuleReflection)
public extension [(AnyHashable, any Operational)] {
 subscript(_ key: AnyHashable) -> (any Operational)? {
  get { first(where: { $0.0 == key })?.1 }
  set {
   guard let index = firstIndex(where: { $0.0 == key }) else {
    if let newValue {
     append((key, newValue))
    }
    return
   }
   if let newValue {
    self[index] = newValue
   } else {
    remove(at: index)
   }
  }
 }
}

@_spi(ModuleReflection)
public extension [(AnyHashable, any AsyncOperation)] {
 subscript(_ key: AnyHashable) -> (any AsyncOperation)? {
  get { first(where: { $0.0 == key })?.1 }
  set {
   guard let index = firstIndex(where: { $0.0 == key }) else {
    if let newValue {
     append((key, newValue))
    }
    return
   }
   if let newValue {
    self[index] = newValue
   } else {
    remove(at: index)
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
  self.compactMap { result in
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

  return self.compactMap { result in
   if let array = result as? Self {
    array._validResults
   } else {
    _isValid(result) ? result : nil
   }
  }
 }
}
