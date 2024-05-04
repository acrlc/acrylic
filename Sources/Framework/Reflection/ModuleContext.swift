import Core
import Foundation

/// A context class for sharing and updating the state across modules
open class ModuleContext:
 @unchecked Sendable, Identifiable, Equatable, Operational {
 @_spi(ModuleReflection)
 public static let unknown = ModuleContext()
 @_spi(ModuleReflection)
 public typealias Indices = ModuleIndex.Indices

 public enum State: Int8, CaseIterable {
  case initial = -1, active, idle, terminal
 }

 @_spi(ModuleReflection)
 @Reflection
 public var state: State = .initial
 @_spi(ModuleReflection)
 public var actor: StateActor!
 @_spi(ModuleReflection)
 public var tasks = Tasks()
 @_spi(ModuleReflection)
 public var cache = [Int: ModuleContext]()

 @_spi(ModuleReflection)
 public var index: ModuleIndex = .start
 @_spi(ModuleReflection)
 public var modules: Modules = .empty
 @_spi(ModuleReflection)
 public var indices: Indices = .empty
 @_spi(ModuleReflection)
 public var values = [Int: Any]()
  
 /// - Note: Results feature not implemented but may return in some form
 ///
 // @_spi(ModuleReflection)
 /// Results returned from calling `tasks`
 // var results = [Int: [Int: Sendable]]()

 @_spi(ModuleReflection)
 public lazy var properties: DynamicProperties? = nil

 @_spi(ModuleReflection)
 public nonisolated(unsafe) init() {}

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

 deinit { self.cancel() }
}

@_spi(ModuleReflection)
public extension ModuleContext {
 @Reflection
 func callTasks() async throws {
  if tasks.queue.notEmpty {
   try await tasks()
  }

  if indices.count > 1 {
   for index in indices[1...] {
    let key = index.key
    if let tasks = cache[key]?.tasks, tasks.queue.notEmpty {
     try await tasks()
    }
   }
  }
 }

 /// Allow all called tasks to finish, including detached tasks
 func wait() async throws {
  try await tasks.wait()

  for task in cache.map(\.1.tasks) {
   try await task.wait()
  }
 }

 nonisolated var isCancelled: Bool { tasks.isCancelled }

 nonisolated(unsafe) func cancel() {
  tasks.cancel()

  for (_, context) in cache {
   context.cancel()
  }
 }

 /// Cancels all tasks including the subsequent, without removing queued
 /// queued
 ///
 func cancel() async {
  await tasks.cancel()
  await cache.values.queue { context in await context.cancel() }
 }

 /// Cancels all tasks including the subsequent, while removing queued
 /// tasks
 ///
 func invalidate() async {
  await tasks.invalidate()
  await cache.values.queue { context in await context.invalidate() }
 }

 nonisolated func invalidateSubrange() {
   indices.removeSubrange(1...)
   modules.removeSubrange(1...)
 }
}

// MARK: - Public
@Reflection(unsafe)
public extension ModuleContext {
 func callAsFunction() async throws {
  try await update()
  try await callTasks()
  state = .idle
 }

 func update() async throws {
  switch state {
  case .active:
   state = .terminal
   try await actor.update()
  case .idle:
   await cancel()
  case .initial:
   state = .idle
  case .terminal:
   throw CancellationError()
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
