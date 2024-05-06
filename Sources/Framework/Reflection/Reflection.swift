@globalActor
public actor Reflection:
 @unchecked Sendable, Identifiable, Equatable {
 public static let shared = Reflection()
 @_spi(ModuleReflection)
 public nonisolated(unsafe) var states: [Int: StateActor] = .empty

 @_spi(ModuleReflection)
 @Reflection
 public static var states: [Int: StateActor] {
  get { shared.states }
  set { shared.states = newValue }
 }

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
  resultType: T.Type = T.self, body: @Reflection () throws -> T
 ) rethrows -> T {
  try body()
 }

 @_spi(ModuleReflection)
 public static func assumeIsolatedModify<T>(
  resultType: T.Type = T.self, 
  _ operation:  @escaping (isolated Reflection) throws -> T,
  file: StaticString = #fileID,
  line: UInt = #line
 ) rethrows -> T {
  try Reflection.shared.assumeIsolated(
   {  try operation($0) },
   file: file,
   line: line
  )
 }
 
 @_spi(ModuleReflection)
 @Reflection
 public static func modify<T: Sendable>(
  resultType: T.Type = T.self, body: @Reflection (Reflection) throws -> T
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
 @usableFromInline
 @discardableResult
 static func cacheIfNeeded<A: StaticModule, B: StateActor>(
  moduleType: A.Type,
  stateType: B.Type
 ) -> B {
  let key = A._mangledName.hashValue

  guard let state = states[key] as? B else {
   let initialState: B = .unknown
   var state: B {
    get { states[key].unsafelyUnwrapped as! B }
    set { states[key] = newValue }
   }

   // store state so it can be referenced from `Reflection.states`
   state = initialState
   initialState.bind([A.shared])
   
   let index = initialState.context.index

   index.element.prepareContext(from: index, actor: initialState)

   Task {
    try await initialState.update()
   }

   return initialState
  }
  return state
 }

 @usableFromInline
 static func callIfNeeded<A: StaticModule, B: StateActor>(
  moduleType: A.Type,
  stateType: B.Type
 ) -> B {
  let key = A._mangledName.hashValue

  guard let state = states[key] as? B else {
   let initialState: B = .unknown
   var state: B {
    get { states[key].unsafelyUnwrapped as! B }
    set { states[key] = newValue }
   }

   state = initialState
   initialState.bind([A.shared])

   let index = initialState.context.index

   index.element.prepareContext(from: index, actor: initialState)

   Task { @Reflection in
    try await initialState.update()
    try await initialState.context.callTasks()
   }

   return initialState
  }
  let context = state.context

  // if module was cached beforehand, but never called
  if context.state == .initial {
   context.state = .idle
   Task { try await context.callAsFunction() }
  }
  return state
 }

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

 @usableFromInline
 @discardableResult
 static func cacheIfNeeded<A: StateActor>(
  id: AnyHashable,
  module: some Module,
  stateType: A.Type
 ) async throws -> A {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   let initialState: A = .unknown
   var state: A {
    get { states[key].unsafelyUnwrapped as! A }
    set { states[key] = newValue }
   }

   state = initialState
   initialState.bind([module])
   
   let index = initialState.context.index

   index.element.prepareContext(from: index, actor: initialState)

   try await initialState.update()
   return initialState
  }
  return state
 }

 @usableFromInline
 @discardableResult
 static func cacheIfNeeded<A: StateActor>(
  id: AnyHashable,
  module: some Module,
  stateType: A.Type
 ) -> A {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   let initialState: A = .unknown
   var state: A {
    get { states[key].unsafelyUnwrapped as! A }
    set { states[key] = newValue }
   }

   state = initialState
   state.bind([module])

   let index = state.context.index
   index.element.prepareContext(from: index, actor: state)

   Task { try await state.update() }
   return state
  }
  return state
 }

 @usableFromInline
 @discardableResult
 static func asyncCacheIfNeeded<A: StateActor>(
  id: AnyHashable,
  module: some Module,
  stateType: A.Type
 ) async throws -> A {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   let initialState: A = .unknown
   var state: A {
    get { states[key].unsafelyUnwrapped as! A }
    set { states[key] = newValue }
   }

   state = initialState
   state.bind([module])

   let index = state.context.index
   index.element.prepareContext(from: index, actor: state)

   try await state.update()
   return state
  }
  return state
 }

 /// Enables repeated calls from a base module using an id to retain state
 @discardableResult
 @usableFromInline
 static func call<A: StateActor>(
  id: AnyHashable,
  module: some Module,
  stateType: A.Type
 ) async throws -> ModulePointer {
  let key = (id.base as? Int) ?? id.hashValue

  guard let state = states[key] as? A else {
   let initialState: A = .unknown
   var state: A {
    get { states[key].unsafelyUnwrapped as! A }
    set { states[key] = newValue }
   }
   
   state = initialState
   state.bind([module])
   
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

 @inlinable
 static func cacheOrCall(
  id: AnyHashable, module: some Module, stateType: (some StateActor).Type,
  call: Bool
 ) async throws {
  if call {
   try await Reflection.call(id: id, module: module, stateType: stateType)
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
 func contextInfo(_ id: AnyHashable? = nil) -> [String] {
  let key = id?.hashValue ?? __key
  let states = Reflection.shared.states

  guard let state = states[key] else {
   return .empty
  }

  let context = state.context
  let cache = context.cache

  let contextInfo = "contexts: " + cache.count.description.readable
  let reflectionInfo = "reflections: " + states.count.description.readable
  let tasksInfo = "tasks: " +
   cache.map {
    let tasks = $0.1.tasks
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
