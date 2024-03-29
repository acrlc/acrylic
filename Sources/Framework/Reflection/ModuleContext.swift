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
 @usableFromInline
 var values: [AnyHashable: Any] = .empty
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
    let module = index.value
    let id = {
     if module.isIdentifiable {
      let description = String(describing: module.id).readableRemovingQuotes
      if description != "nil" {
       return "\(description)(\(index.hashValue))".hashValue
      }
     }
     return index.hashValue
    }()
    guard
     let context: ModuleContext = (
      ModuleContext.cache.withLockUnchecked { $0[id] }
     ) else {
     #if DEBUG
     print(index, "was Deallocated", separator: .newline)
     #endif
     continue
    }

    let offset = index.offset

    context.tasks.cancel()
    index.base.remove(at: offset)
    index.elements.remove(at: offset)
    _ = ModuleContext.cache.withLockUnchecked { $0.removeValue(forKey: id) }
   }
  }
 }

 @_spi(ModuleReflection)
 @inlinable
 var isRunning: Bool {
  index.withLockUnchecked { index in
   self.tasks.isRunning &&
    index.elements.dropFirst().contains(
     where: { index in
      let module = index.value
      return Self.cache.withLockUnchecked {
       $0[module._id(from: index)]?.tasks.isRunning ==
        true
      }
     }
    )
  }
 }
}

/* MARK: - Update Functions */
public extension ModuleContext {
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

 func update() {
  updateTask = Task {
   state.update(self)
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
    let baseModule = baseIndex.value

    self.results = .empty
    self.results![baseModule._id(from: baseIndex)] = try await self.tasks()

    let baseElements = baseIndex.elements
    guard baseElements.count > 1 else {
     return
    }
    let elements = baseElements.dropFirst()
    for index in elements {
     let module = index.value
     guard let context = module._context(from: index) else {
      continue
     }

     self.results![module._id(from: index)] = try await context.tasks()
    }
   }
   self.calledTask = task
   return task
  }.value
 }
}

/* MARK: - Module Extensions*/
@_spi(ModuleReflection)
public extension Module {
 func _id(from index: ModuleState.Index) -> Int {
  if isIdentifiable {
   let description = String(describing: id).readableRemovingQuotes
   if description != "nil" {
    return "\(description)(\(index.hashValue))".hashValue
   }
  }
  return index.hashValue
 }

 func _context(from index: ModuleState.Index) -> ModuleContext? {
  ModuleContext.cache.withLockUnchecked { $0[self._id(from: index)] }
 }
}
