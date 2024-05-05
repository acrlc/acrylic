import Core
import Foundation

/// A context class for sharing and updating the state across modules
open class ModuleContext:
 @unchecked Sendable, Identifiable, Equatable, Operational {
 @_spi(ModuleReflection)
 public static let unknown = ModuleContext()
 @_spi(ModuleReflection)
 public typealias Indices = ModuleIndex.Indices

 public enum State: Int8 {
  case initial = -1, active, idle, terminal
 }

 @Reflection
 public var state: State = .initial
 @_spi(ModuleReflection)
 public var actor: StateActor!
 public var tasks: Tasks = .empty
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
 public nonisolated(unsafe) init() {}
 deinit { self.cancel() }
}

@_spi(ModuleReflection)
@Reflection
public extension ModuleContext {
 @Tasks
 func callTasks() async throws {
  try await tasks()

  for index in indices[1...] {
   try await cache[index.key].unsafelyUnwrapped.tasks()
  }
 }

 nonisolated func invalidateSubrange() {
  indices.removeSubrange(1...)
  modules.removeSubrange(1...)
 }
}

// MARK: - Public
@Reflection(unsafe)
public extension ModuleContext {
 @Tasks
 /// Cancels all tasks including the subsequent, while removing queued tasks
 ///
 func invalidate() {
  tasks.invalidate()
  for context in cache.values {
   context.invalidate()
  }
 }

 nonisolated var isCancelled: Bool { tasks.isCancelled }

 /// Cancels all tasks including the subsequent, without removing queued tasks
 ///
 nonisolated func cancel() {
  tasks.cancel()

  for context in cache.values {
   context.cancel()
  }
 }
 
 func cancel() async {
  await tasks.cancel()
  
  for context in cache.values {
   await context.cancel()
  }
 }

 /// Wait for the current call to finish, excluding detached tasks
 nonisolated func wait() async throws {
  try await tasks.wait()

  for context in cache.values {
   try await context.wait()
  }
 }

 /// Wait for all called tasks to finish, including detached tasks
 nonisolated func waitForAll() async throws {
  try await tasks.waitForAll()

  for context in cache.values {
   try await context.waitForAll()
  }
 }

 func callAsFunction() async throws {
  try await update()

  state = .active
  defer { state = .idle }

  try await callTasks()
 }

 func update() async throws {
  switch state {
  case .active:
   state = .terminal
   try await actor.update()
  case .idle: await cancel()
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
   to unwrap, wait until context is loaded, or assign and identical ID to a \
   contained module.
   """
  )
  return context.unsafelyUnwrapped
 }

 @inline(__always)
 subscript<ID: Hashable>(checkedID id: ID) -> ModuleContext? {
  cache.values.first(where: { $0.index.element.id as? ID ~= id })
 }
}

@Reflection(unsafe)
public extension ModuleContext {
 @inline(__always)
 /// Restarts a subcontext based on a module's `id` property.
 ///
 /// - Parameters:
 ///   - id: The `id` property of the module that needs to be restarted
 ///
 /// - Throws: Any potential error from the targeted module
 ///
 func restart(_ id: some Hashable) async throws {
  let tasks = self[id].tasks
  await tasks.cancel()
  try await tasks()
 }
}
