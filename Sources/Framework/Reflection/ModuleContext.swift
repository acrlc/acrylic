import Core

/// A context class for sharing and updating the state across modules
public actor ModuleContext: @unchecked Sendable, Identifiable,
 Equatable /* , Operational can't be met due to actor isolated `cancel()` */ {
 public static let shared = ModuleContext()

 // TODO: Rely on self owned cache instead of shared
 @_spi(ModuleReflection)
 public nonisolated lazy var cache = [AnyHashable: ModuleContext]()
 @_spi(ModuleReflection)
 public static var cache: [AnyHashable: ModuleContext] {
  get { shared.cache }
  set { shared.cache = newValue }
 }

 public nonisolated
 lazy var state: ModuleState = .unknown
 public nonisolated
 lazy var index = ModuleState.Index.start

 /// Stored values that are relevant to framework specific property wrappers
 @usableFromInline
 nonisolated lazy var values = [AnyHashable: Any]()

 public nonisolated lazy var tasks = Tasks()

 /// The currently executing background task
 public nonisolated
 lazy var backgroundTask: Task<(), Error>? = nil
 /// The currently executing `tasks`
 public nonisolated
 lazy var calledTask: Task<(), Error>? = nil

 /// The cancellation task
 public nonisolated
 lazy var cancellationTask: Task<(), Never>? = nil

 /// Results returned from calling `tasks`
 @_spi(ModuleReflection)
 public lazy var results: [AnyHashable: [AnyHashable: Sendable]] = .empty

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
 deinit {
  calledTask?.cancel()
  backgroundTask?.cancel()
  self.cache = .empty
 }
}

public extension ModuleContext {
 /// Cancels all tasks in reverse including the subsequent and removes elements
 func cancel() async {
  await cancellationTask?.wait()
  cancellationTask = Task {
   if let calledTask {
    calledTask.cancel()
   }

   let baseIndices = index.indices

   guard baseIndices.count > 1 else {
    return
   }
   let indices = baseIndices.dropFirst()

   for index in indices.reversed() {
    let key = index.key
    let context = cache[key].unsafelyUnwrapped
    let offset = index.offset

    await context.tasks.cancel()
    index.base.remove(at: offset)
    index.indices.remove(at: offset)

    self.cache.removeValue(forKey: key)
   }
   await tasks.cancel()
  }
 }

 func cancelAndWait() async {
  await cancel()
  await cancellationTask?.wait()
 }

 @inlinable
 nonisolated var isRunning: Bool { tasks.isRunning }

 /// Allow all called tasks to finish, excluding detached tasks
 @inlinable
 func wait() async throws {
  try await calledTask?.wait()
  try await tasks.wait()
 }

 /// Allow all called tasks to finish, including detached tasks
 @inlinable
 func waitForAll() async throws {
  try await calledTask?.wait()
  try await tasks.waitForAll()
 }
}

/* MARK: - Update Functions */
public extension ModuleContext {
 @inline(__always)
 func callAsFunction() async throws {
  try await state.callAsFunction(self)
 }

 @inline(__always)
 func update() async {
  await state.update(self)
 }

 nonisolated func callAsFunction(state: ModuleState) {
  backgroundTask?.cancel()
  backgroundTask = Task {
   self.backgroundTask?.cancel()
   try await state.callAsFunction(self)
  }
 }

 nonisolated func callAsFunction() {
  backgroundTask?.cancel()
  backgroundTask = Task {
   try await state.callAsFunction(self)
  }
 }

 nonisolated func callAsFunction(prior: ModuleContext) {
  backgroundTask?.cancel()
  backgroundTask = Task {
   try await state.callAsFunction(self)
   await state.update(prior)
  }
 }
}

public extension ModuleContext {
 func callTasks() async throws {
  #if DEBUG
  assert(!(calledTask?.isRunning ?? false))
  #endif
  let task = Task {
   let baseIndex = index
   results = .empty
   results[baseIndex.key] = try await tasks()
   let baseIndices = baseIndex.indices
   guard baseIndices.count > 1 else {
    return
   }

   let elements = baseIndices.dropFirst().map {
    ($0, self.cache[$0.key].unsafelyUnwrapped)
   }

   for (index, context) in elements where index.checkedElement != nil {
    results[index.key] = try await context.tasks()
   }
  }

  calledTask = task
  try await task.value
 }
}
