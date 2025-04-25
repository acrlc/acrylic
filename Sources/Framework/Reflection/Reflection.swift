import struct Core.KeyValueStorage

@globalActor
public actor Reflection:
 @unchecked Sendable, Identifiable, Equatable {
 public static let shared = Reflection()
 public static var keys: Set<Int> = .empty
 @_spi(ModuleReflection)
 @Reflection
 public static var states = KeyValueStorage<StateActor>()

 @_spi(ModuleReflection)
 public static func assumeIsolated<T>(
  _ operation: @escaping () throws -> T,
  file: StaticString = #fileID,
  line: UInt = #line
 ) rethrows -> T {
  try Reflection.shared.assumeIsolated(
   { _ in try operation() },
   file: file,
   line: line
  )
 }

 @_spi(ModuleReflection)
 @Reflection
 public static func run<T: Sendable>(
  resultType _: T.Type = T.self,
  body: @Reflection () throws -> T
 ) rethrows -> T {
  try body()
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func task<T: Sendable>(
  priority: TaskPriority? = nil,
  resultType _: T.Type = T.self,
  body: @Reflection @escaping () throws -> T,
  onResult: @escaping (T) -> Void,
  onError: @escaping (any Error) -> Void
 ) -> Task<Void, Never> {
  Task.detached(priority: priority) { @Reflection in
   do {
    try onResult(body())
   } catch {
    onError(error)
   }
  }
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func task<T: Sendable>(
  priority: TaskPriority? = nil,
  resultType _: T.Type = T.self,
  body: @Reflection @escaping () throws -> T,
  onResult: @escaping (T) -> Void
 ) -> Task<Void, any Error> {
  Task.detached(priority: priority) { @Reflection in
   try onResult(body())
  }
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func task<T: Sendable>(
  priority: TaskPriority? = nil,
  resultType _: T.Type = T.self,
  body: @Reflection @escaping () throws -> T,
  onError: @escaping (any Error) -> Void
 ) -> Task<T?, Never> {
  Task.detached(priority: priority) { @Reflection in
   do {
    return try body()
   } catch {
    onError(error)
   }
   return nil
  }
 }

 @_spi(ModuleReflection)
 @discardableResult
 public static func task<T: Sendable>(
  priority: TaskPriority? = nil,
  resultType _: T.Type = T.self,
  body: @Reflection @escaping () throws -> T
 ) -> Task<T, any Error> {
  Task.detached(priority: priority) { @Reflection in try body() }
 }

 @_spi(ModuleReflection)
 public static func assumeIsolatedModify<T>(
  resultType _: T.Type = T.self,
  _ operation: @escaping (isolated Reflection) throws -> T,
  file: StaticString = #fileID,
  line: UInt = #line
 ) rethrows -> T {
  try Reflection.shared.assumeIsolated(
   { try operation($0) },
   file: file,
   line: line
  )
 }

 @_spi(ModuleReflection)
 @Reflection
 public static func modify<T: Sendable>(
  resultType _: T.Type = T.self, body: @Reflection (Reflection) throws -> T
 ) rethrows -> T {
  try body(shared)
 }

 public static func == (lhs: Reflection, rhs: Reflection) -> Bool {
  lhs.id == rhs.id
 }
}

@_spi(ModuleReflection)
@Reflection
extension Reflection {
 /* FIXME: cache wrapped properties that are modules, as well */
 @preconcurrency
 @usableFromInline
 @discardableResult
 static func cacheIfNeeded<A: StaticModule, B: StateActor>(
  moduleType _: A.Type,
  stateType _: B.Type
 ) -> B {
  let key = A._mangledName.hashValue

  guard let state = states[key] else {
   states.store(B.unknown, for: key)
   var state: B {
    get { states[unchecked: key] as! B }
    set { states[key] = newValue }
   }

   // store state so it can be referenced from `Reflection.states`
   state.bind([A.shared])

   let index = state.context.index

   index.element.prepareContext(from: index, actor: state)

   Task(priority: .high) { @Reflection in
    try await state.update()
   }

   return state
  }
  return state as! B
 }

 @preconcurrency
 @usableFromInline
 static func callIfNeeded<A: StaticModule, B: StateActor>(
  moduleType _: A.Type,
  stateType _: B.Type
 ) -> B {
  let key = A._mangledName.hashValue

  guard let state = states[key] as? B else {
   states.store(B.unknown, for: key)
   var state: B {
    get { states[unchecked: key] as! B }
    set { states[key] = newValue }
   }

   state.bind([A.shared])

   let index = state.context.index

   index.element.prepareContext(from: index, actor: state)

   Task(priority: .high) { @Reflection in
    try await state.update()
    try await state.context.callTasks()
   }

   return state
  }
  let context = state.context

  // if module was cached beforehand, but never called
  if context.state == .initial {
   context.state = .idle
   Task { try await context.callAsFunction() }
  }
  return state
 }

 @preconcurrency
 @inlinable
 @discardableResult
 static func cacheOrCall<A: StateActor>(
  moduleType: (some StaticModule).Type,
  stateType: A.Type,
  call: Bool
 ) -> A {
  if call {
   Reflection.callIfNeeded(
    moduleType: moduleType, stateType: stateType
   )
  } else {
   Reflection.cacheIfNeeded(
    moduleType: moduleType, stateType: stateType
   )
  }
 }

 @preconcurrency
 @usableFromInline
 @discardableResult
 static func cacheIfNeeded<A: StateActor>(
  id: AnyHashable,
  module: @autoclosure () -> some Module,
  stateType _: A.Type
 ) async throws -> A {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   states.store(A.unknown, for: key)
   var state: A {
    get { states[unchecked: key] as! A }
    set { states[key] = newValue }
   }

   state.bind([module()])

   let index = state.context.index

   index.element.prepareContext(from: index, actor: state)

   try await state.update()
   return state
  }
  return state
 }

 @preconcurrency
 @usableFromInline
 @discardableResult
 static func cacheIfNeeded<A: StateActor>(
  id: AnyHashable,
  module: @autoclosure () -> some Module,
  stateType _: A.Type
 ) -> A {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   states.store(A.unknown, for: key)
   var state: A {
    get { states[unchecked: key] as! A }
    set { states[key] = newValue }
   }

   state.bind([module()])

   let index = state.context.index
   index.element.prepareContext(from: index, actor: state)

   Task(priority: .high) { @Reflection in try await state.update() }
   return state
  }
  return state
 }

 @preconcurrency
 @usableFromInline
 @discardableResult
 static func asyncCacheIfNeeded<A: StateActor>(
  id: AnyHashable,
  module: @autoclosure () -> some Module,
  stateType _: A.Type
 ) async throws -> A {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   states.store(A.unknown, for: key)
   var state: A {
    get { states[unchecked: key] as! A }
    set { states[key] = newValue }
   }

   state.bind([module()])

   let index = state.context.index
   index.element.prepareContext(from: index, actor: state)

   try await state.update()
   return state
  }
  return state
 }

 @preconcurrency
 @discardableResult
 @usableFromInline
 static func callModulePointer<A: StateActor>(
  id: AnyHashable,
  module: @autoclosure () -> some Module,
  stateType _: A.Type
 ) -> ModulePointer {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   let initialState: A = .unknown
   var state: A {
    get { states[key].unsafelyUnwrapped as! A }
    set { states[key] = newValue }
   }

   state = initialState
   state.bind([module()])

   let index = initialState.context.index

   index.element.prepareContext(from: index, actor: initialState)

   Task(priority: .high) { @Reflection in
    try await initialState.update()
    try await initialState.context.callTasks()
   }

   return withUnsafeMutablePointer(to: &index.element) { $0 }
  }

  Task(priority: .high) { @Reflection in
   try await state.context.callAsFunction()
  }

  let index = state.context.index
  return withUnsafeMutablePointer(to: &index.element) { $0 }
 }

 /// Enables repeated calls from a base module using an id to retain state
 @discardableResult
 @usableFromInline
 static func callAsyncModulePointer<A: StateActor>(
  id: AnyHashable,
  module: @autoclosure () -> some Module,
  stateType _: A.Type
 ) async throws -> ModulePointer {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   let initialState: A = .unknown
   var state: A {
    get { states[key].unsafelyUnwrapped as! A }
    set { states[key] = newValue }
   }

   state = initialState
   state.bind([module()])

   let index = initialState.context.index

   index.element.prepareContext(from: index, actor: initialState)
   try await initialState.update()
   try await initialState.context.callTasks()

   return withUnsafeMutablePointer(to: &index.element) { $0 }
  }

  try await state.context.callAsFunction()

  let index = state.context.index
  return withUnsafeMutablePointer(to: &index.element) { $0 }
 }

 @discardableResult
 @usableFromInline
 static func call<A: StateActor>(
  id: AnyHashable,
  module: @autoclosure () -> some Module,
  stateType _: A.Type
 ) -> A {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   let initialState: A = .unknown
   var state: A {
    get { states[key].unsafelyUnwrapped as! A }
    set { states[key] = newValue }
   }

   state = initialState
   state.bind([module()])

   let index = initialState.context.index

   index.element.prepareContext(from: index, actor: initialState)

   Task(priority: .high) { @Reflection in
    try await initialState.update()
    try await initialState.context.callTasks()
   }

   return initialState
  }

  Task(priority: .high) { @Reflection in
   try await state.context.callAsFunction()
  }

  return state
 }

 @discardableResult
 @usableFromInline
 static func callAsync<A: StateActor>(
  id: AnyHashable,
  module: @autoclosure () -> some Module,
  stateType _: A.Type
 ) async throws -> A {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   let initialState: A = .unknown
   var state: A {
    get { states[key].unsafelyUnwrapped as! A }
    set { states[key] = newValue }
   }

   state = initialState
   state.bind([module()])

   let index = initialState.context.index

   index.element.prepareContext(from: index, actor: initialState)
   try await initialState.update()
   try await initialState.context.callTasks()

   return initialState
  }

  try await state.context.callAsFunction()

  return state
 }

 @preconcurrency
 @discardableResult
 @inlinable
 static func cacheOrCall<A: StateActor>(
  id: AnyHashable,
  module: @autoclosure () -> some Module,
  stateType: A.Type,
  call: Bool
 ) -> A {
  if call {
   Reflection.call(id: id, module: module(), stateType: stateType)
  } else {
   Reflection.cacheIfNeeded(
    id: id,
    module: module(),
    stateType: stateType
   )
  }
 }

 @preconcurrency
 @discardableResult
 @inlinable
 static func asyncCacheOrCall<A: StateActor>(
  id: AnyHashable,
  module: some Module,
  stateType: A.Type,
  call: Bool
 ) async throws -> A {
  if call {
   try await Reflection.callAsync(id: id, module: module, stateType: stateType)
  } else {
   try await Reflection.cacheIfNeeded(
    id: id,
    module: module,
    stateType: stateType
   )
  }
 }
}

// MARK: - Module Extensions
@_spi(ModuleReflection)
public extension Module {
 @preconcurrency @Reflection
 func contextInfo(_ id: AnyHashable? = nil) -> [String] {
  let key = id?.hashValue ?? __key

  guard let state = Reflection.states[key] else {
   return .empty
  }

  let context = state.context
  let contexts = context.cache.values

  let contextInfo = "contexts: " + contexts.count.description.readable
  let reflectionInfo = "reflections: " +
   Reflection.states.count.description.readable
  let tasksInfo = "tasks: " +
   contexts.map {
    let tasks = $0.tasks
    return tasks.running.count + tasks.queue.count
   }
   .reduce(into: 0, +=).description.readable

  let index = context.index
  let indexInfo = "indices: " + index.indices.count.description.readable
  let valuesInfo = "values: " + index.base.count.description.readable

  return [
   contextInfo,
   reflectionInfo,
   tasksInfo,
   indexInfo,
   valuesInfo
  ]
 }
}
