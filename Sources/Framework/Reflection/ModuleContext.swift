import Core
import Foundation

/// A context class for sharing and updating the state across modules
open class ModuleContext:
 @unchecked Sendable, Identifiable, Equatable, Operational {
 @_spi(ModuleReflection)
 public static let unknown = ModuleContext()
 @_spi(ModuleReflection)
 public typealias Indices = ModuleIndex.Indices

 public enum State: UInt8, Sendable, Comparable, Equatable {
  case terminal, initial, idle, active

  public static func < (
   lhs: ModuleContext.State, rhs: ModuleContext.State
  ) -> Bool {
   lhs.rawValue < rhs.rawValue
  }
 }

 public var state: State = .initial

 @_spi(ModuleReflection)
 public var actor: StateActor!
 public var tasks: Tasks = .empty
 @_spi(ModuleReflection)
 public var cache: KeyValueStorage<ModuleContext> = .empty

 @_spi(ModuleReflection)
 public var index: ModuleIndex = .start
 @_spi(ModuleReflection)
 public var modules: Modules = .empty
 @_spi(ModuleReflection)
 public var indices: Indices = .empty
 @_spi(ModuleReflection)
 public var values = ReadWriteLockedValue<AnyKeyValueStorage>(.empty)

 /// - Note: Results feature not implemented but may return in some form
 ///
 // @_spi(ModuleReflection)
 /// Results returned from calling `tasks`
 // var results = [Int: [Int: Sendable]]()

 @_spi(ModuleReflection)
 public lazy var properties: DynamicProperties? = nil

 /// Initializer used for indexing modules
 init(
  index: consuming ModuleIndex,
  actor: consuming some StateActor,
  properties: DynamicProperties? = nil
 ) {
  self.actor = actor
  self.index = index
  if let properties {
   self.properties = properties
  }
 }

 public static func == (lhs: ModuleContext, rhs: ModuleContext) -> Bool {
  lhs.id == rhs.id
 }

 @_spi(ModuleReflection)
 public nonisolated init() {}
 deinit { self.cancel() }
}

@_spi(ModuleReflection)
@Reflection
public extension ModuleContext {
 func invalidateSubrange() {
  indices.removeSubrange(1...)
  modules.removeSubrange(1...)
 }
}

@_spi(ModuleReflection)
@Tasks
public extension ModuleContext {
 func callTasks() async throws {
  try await tasks()

  for context in cache.values {
   try await context.tasks()
  }
 }

 /// Cancel all tasks including the subsequent, while removing queued tasks
 ///
 func invalidate() {
  tasks.invalidate()
  for context in cache.values {
   context.invalidate()
  }
 }

 nonisolated var isCancelled: Bool { tasks.isCancelled }

 /// Cancel all tasks including the subsequent, without removing queued tasks
 ///
 nonisolated func cancel() {
  tasks.cancel()

  for context in cache.values {
   context.cancel()
  }
 }
}

// MARK: - Public Implementation
public extension ModuleContext {
 /// Cancel all tasks including the subsequent, while removing queued tasks
 ///
 func invalidate() async {
  await tasks.invalidate()
  for context in cache.values {
   await context.invalidate()
  }
 }

 /// Cancel all tasks including the subsequent, without removing queued tasks
 ///
 func cancel() async {
  await tasks.cancel()

  for context in cache.values {
   await context.cancel()
  }
 }

 /// Wait for the current call to finish, excluding detached tasks
 func wait() async throws {
  try await tasks.wait()

  for context in cache.values {
   try await context.wait()
  }
 }

 /// Wait for all called tasks to finish, including detached tasks
 func waitForAll() async throws {
  try await tasks.waitForAll()

  for context in cache.values {
   try await context.waitForAll()
  }
 }
}

@Reflection
public extension ModuleContext {
 func callAsFunction() async throws {
  switch state {
  case .active:
   state = .terminal
   try await actor.update()
  case .idle:
   state = .terminal
   await cancel()
  case .terminal:
   throw CancellationError()
  case .initial: break
  }

  state = .active
  defer { state = .idle }

  try await callTasks()
 }

 func update() async throws {
  switch state {
  case .active:
   state = .terminal
   defer { state = .idle }
   try await actor.update()
  case .idle:
   state = .terminal
   defer { state = .idle }
   await cancel()
  case .terminal:
   throw CancellationError()
  case .initial: break
  }
 }

 func callAsFunction(prior: ModuleContext) async throws {
  try await callAsFunction()
  try await prior.update()
 }

 func callAsFunction(with state: ModuleContext.State) async throws {
  self.state = state
  try await callAsFunction()
 }

 func update(with state: ModuleContext.State) async throws {
  self.state = state
  try await update()
 }

 func cancel(with state: ModuleContext.State) async {
  self.state = state
  await cancel()
 }
}

public extension ModuleContext {
 @inline(__always)
 subscript(id: some Hashable) -> ModuleContext {
  let context = self[checkedID: id]
  assert(
   context != nil,
   """
   invalid ID `\(id)` for \(#function), use `subscript(checkedID:)` to \
   to unwrap, wait until context is loaded, or use an ID that matches a module \
   contained within `void`.
   """
  )
  return context.unsafelyUnwrapped
 }

 @inline(__always)
 subscript<ID: Hashable>(checkedID id: ID) -> ModuleContext? {
  cache.values.first(where: { $0.index.element.id as? ID == id })
 }
}

// MARK: - Module Operations
public extension ModuleContext {
 @inline(__always)
 /// Restart a subtask based on a module's `id` property.
 ///
 /// - parameter id: The `id` property of the module that needs to be restarted
 /// - throws: Any potential error returned by the targeted module
 ///
 func restart(_ id: some Hashable) async throws {
  let tasks = self[id].tasks
  await tasks.cancel()
  try await tasks()
 }

 @inline(__always)
 @discardableResult
 /// Restart a subtask based on a module's `id` property.
 ///
 /// - parameter id: The `id` property of the module that needs to be restarted
 /// - throws: Any potential error returned by the targeted module
 ///
 func restart(_ id: some Hashable) -> Task<(), any Error> {
  let tasks = self[id].tasks
  return Tasks.detached {
   await tasks.cancel()
   try await tasks()
  }
 }

 @inline(__always)
 @discardableResult
 /// Restart a subcontext if it exists.
 ///
 /// - parameter id: The `id` property of the module that needs to be restarted
 /// - throws: Any potential error returned by the targeted module
 ///
 func restartIfAvailable(_ id: some Hashable) -> Bool {
  guard let tasks = self[checkedID: id]?.tasks else { return false }
  Tasks.detached {
   await tasks.cancel()
   try await tasks()
  }
  return true
 }

 /// Wait for a specific tasks to finish running.
 func wait(on id: some Hashable) async throws {
  let tasks = self[id].tasks
  try await tasks.wait()
 }

 /// Wait for a specific tasks to finish running, along with subtasks.
 func waitForAll(on id: some Hashable) async throws {
  let tasks = self[id].tasks
  try await tasks.waitForAll()
 }
}
