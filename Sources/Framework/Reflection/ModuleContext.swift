import Core

/// A context class for sharing and updating the state across modules
@globalActor
public actor ModuleContext: Identifiable,
 Equatable /* , Operational can't be met due to actor isolated `cancel()` */ {
 public static let shared = ModuleContext()

 public static var cache = [AnyHashable: ModuleContext]()

 public
 nonisolated lazy var state: ModuleState = .unknown
 public nonisolated
 lazy var index = ModuleState.Index.start

 /// Stored values that are relevant to framework specific property wrappers
 @ModuleContext(unsafe)
 @usableFromInline
 lazy var values = [AnyHashable: Any]()

 public nonisolated
 lazy var tasks = Tasks(id: self.id)

 /// The currently executing update function
 public nonisolated
 lazy var updateTask: Task<(), Error>? = nil
 public nonisolated
 lazy var calledTask: Task<(), Error>? = nil

 /// Results returned from calling `tasks`
 @_spi(ModuleReflection)
 @ModuleContext(unsafe)
 public lazy var results: [AnyHashable: Sendable] = .empty

 @_spi(ModuleReflection)
 public nonisolated
 lazy var properties: DynamicProperties? = nil

 /// Initializer used for indexing modules
 init(
  index: ModuleIndex,
  state: ModuleState,
  properties: DynamicProperties? = nil
 ) {
  self.index = index
  self.state = state
  self.properties = properties
 }

 public static func == (lhs: ModuleContext, rhs: ModuleContext) -> Bool {
  lhs.id == rhs.id
 }

 init() {}
 deinit { self.calledTask?.cancel() }
}

public extension ModuleContext {
 /// Cancels all tasks in reverse including the subsequent and removes elements
 @ModuleContext
 func cancel() {
  if let calledTask {
   calledTask.cancel()
  }

  if let updateTask {
   updateTask.cancel()
  }

  tasks.cancel()
  let baseIndices = index.indices

  guard baseIndices.count > 1 else {
   return
  }
  let indices = baseIndices.dropFirst()

  for index in indices.reversed() {
   let key = index.key
   let context = index.context.unsafelyUnwrapped
   let offset = index.offset

   context.tasks.cancel()
   index.base.remove(at: offset)
   index.indices.remove(at: offset)
   ModuleContext.cache.removeValue(forKey: key)
  }
 }

 @inlinable
 nonisolated var isRunning: Bool { tasks.isRunning }

 /// Allow all called tasks to finish, excluding detached tasks
 @inlinable
 func wait() async throws {
  try await calledTask?.wait()
 }

 /// Allow all called tasks to finish, including detached tasks
 @inlinable
 func waitForAll() async throws {
  try await wait()

  for task in tasks.detached {
   try await task.wait()
  }

  let baseIndex = index
  let baseIndices = baseIndex.indices
  guard baseIndices.count > 1 else {
   return
  }

  for tasks in baseIndices.dropFirst().map(\.context!.tasks) {
   for task in tasks.detached {
    try await task.wait()
   }
  }
 }
}

/* MARK: - Update Functions */
public extension ModuleContext {
 @ModuleContext
 @inline(__always)
 func callAsFunction() async throws {
  try await state.callAsFunction(self)
 }

 @ModuleContext
 @inline(__always)
 func update() {
  state.update(self)
 }

 nonisolated func callAsFunction(state: ModuleState) {
  updateTask = Task { @ModuleContext in
   try await state.callAsFunction(self)
  }
 }

 nonisolated func callAsFunction() {
  updateTask = Task { @ModuleContext in
   try await state.callAsFunction(self)
  }
 }

 nonisolated func callAsFunction(prior: ModuleContext) {
  updateTask = Task { @ModuleContext in
   try await state.callAsFunction(self)
   state.update(prior)
  }
 }
}

public extension ModuleContext {
 @ModuleContext
 func callTasks() async throws {
  #if DEBUG
  assert(!(calledTask?.isRunning ?? false))
  #endif
  results = .empty

  let baseIndex = index
  let task = Task {
   self.results = .empty
   self.results[baseIndex.key] = try await self.tasks()

   let baseIndices = baseIndex.indices
   guard baseIndices.count > 1 else {
    return
   }
   let elements = baseIndices.dropFirst().map {
    ($0, $0.context.unsafelyUnwrapped)
   }

   for (index, context) in elements {
    self.results[index.key] = try await context.tasks()
   }
  }

  calledTask = task
  try await task.value
 }
}
