import Core
import struct os.OSAllocatedUnfairLock

/// A context class for sharing and updating the state across modules
public final class ModuleContext: Identifiable, Equatable, Operational {
 public static let shared = ModuleContext()

 public lazy var phase = OSAllocatedUnfairLock<()>(initialState: ())

 public static var cache =
  OSAllocatedUnfairLock<[AnyHashable: ModuleContext]>(initialState: .empty)

 public unowned var state: ModuleState = .unknown
 public var index =
  OSAllocatedUnfairLock<ModuleState.Index>(initialState: .start)

 /// Stored values that are relevant to framework specific property wrappers
// @usableFromInline
// var values: [AnyHashable: Any] = .empty
 @usableFromInline
 var values =
  OSAllocatedUnfairLock<[AnyHashable: Any]>(initialState: .empty)

 public lazy var tasks = Tasks(id: self.id)

 /// The currently executing update function
 public var updateTask: Task<(), Error>?
 public var calledTask: Task<(), Error>?

 /// Results returned from calling `tasks`
 @_spi(ModuleReflection)
 public var results: [AnyHashable: Sendable]?

 @_spi(ModuleReflection)
 public lazy var properties: DynamicProperties? = nil

 /// Initializer used for indexing modules
 init(
  index: ModuleIndex,
  state: ModuleState,
  properties: DynamicProperties? = nil
 ) {
  self.index.withLockUnchecked { $0 = index }
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
 @inlinable
 func cancel() {
  if let calledTask {
   calledTask.cancel()
  }

  if let updateTask {
   updateTask.cancel()
  }

  tasks.cancel()
  index.withLockUnchecked { baseIndex in
   let baseElements = baseIndex.elements

   guard baseElements.count > 1 else {
    return
   }
   let elements = baseElements.dropFirst()

   for index in elements.reversed() {
    let key = index.key
    let context = index.context.unsafelyUnwrapped
    let offset = index.offset

    context.tasks.cancel()
    index.base.remove(at: offset)
    index.elements.remove(at: offset)
    _ = ModuleContext.cache.withLockUnchecked { $0.removeValue(forKey: key) }
   }
  }
 }

 @inlinable
 var isRunning: Bool { tasks.isRunning }

 /// Allow all called tasks to finish, excluding detached tasks
 @inlinable
 func wait() async throws {
  try await calledTask?.wait()
 }

 /// Allow all called tasks to finish, including detached tasks
 @inlinable
 func waitForAll() async throws {
  try await wait()
  assert(tasks.isEmpty)

  for task in tasks.detached {
   try await task.wait()
  }

  try await index.withLockUnchecked { baseIndex in
   let baseIndex = baseIndex
   return Task {
    let baseElements = baseIndex.elements
    guard baseElements.count > 1 else {
     return
    }

    for tasks in baseElements.dropFirst().map(\.context!.tasks) {
     for task in tasks.detached {
      try await task.wait()
     }
    }
   }
  }.value
 }
}

/* MARK: - Update Functions */
public extension ModuleContext {
 @inline(__always)
 func callAsFunction() async throws {
  try await state.callAsFunction(self)
 }

 @inline(__always)
 func update() async throws {
  state.update(self)
 }

 func callAsFunction(state: ModuleState) {
  updateTask = Task {
   try await state.callAsFunction(self)
  }
 }

 func callAsFunction() {
  updateTask = Task {
   try await state.callAsFunction(self)
  }
 }

 func callAsFunction(prior: ModuleContext) {
  updateTask = Task {
   try await state.callAsFunction(self)
   state.update(prior)
  }
 }
}

public extension ModuleContext {
 func callTasks() async throws {
  #if DEBUG
  assert(!(calledTask?.isRunning ?? false))
  #endif
  try await index.withLockUnchecked { baseIndex in
   let baseIndex = baseIndex

   let task = Task {
    self.results = .empty
    self.results![baseIndex.key] = try await self.tasks()

    let baseElements = baseIndex.elements
    guard baseElements.count > 1 else {
     return
    }
    let elements = baseElements.dropFirst().map {
     ($0, $0.context.unsafelyUnwrapped)
    }

    for (index, context) in elements {
     self.results![index.key] = try await context.tasks()
    }
   }

   self.calledTask = task
   return task
  }.value
 }
}
