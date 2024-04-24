@globalActor
public actor Reflection:
 @unchecked Sendable, Identifiable, Equatable {
 public static let shared = Reflection()
 @Reflection
 public var states: [AnyHashable: ModuleState] = .empty

 @Reflection
 public static var states: [AnyHashable: ModuleState] {
  get { shared.states }
  set { shared.states = newValue }
 }

 public static func == (lhs: Reflection, rhs: Reflection) -> Bool {
  lhs.id == rhs.id
 }
}

@Reflection
extension Reflection {
 /* FIXME: cache wrapped properties that are modules, as well */
 @usableFromInline
 @discardableResult
 static func cacheIfNeeded<A: StaticModule>(
  _ moduleType: A.Type
 ) -> ModuleState {
  guard let state = states[A._mangledName] else {
   let initialState = ModuleState()
   unowned var state: ModuleState {
    get { states[A._mangledName].unsafelyUnwrapped }
    set {
     states[A._mangledName] = newValue
    }
   }

   // store state so it can be referenced from `Reflection.states`
   state = initialState

   let values =
    withUnsafeMutablePointer(to: &state.values) { $0 }
   let indices =
    withUnsafeMutablePointer(to: &state.indices) { $0 }

   ModuleIndex.bind(
    base: [A.shared],
    basePointer: values,
    indicesPointer: indices
   )

   let index = initialState.indices[0]

   initialState.mainContext = .cached(index, with: initialState, key: index.key)

   index.step(initialState.recurse)

   return initialState
  }
  return state
 }

 @usableFromInline
 static func callIfNeeded<A: StaticModule>(_ moduleType: A.Type) {
  if states[A._mangledName] == nil {
   let initialState = ModuleState()
   unowned var state: ModuleState {
    get { states[A._mangledName].unsafelyUnwrapped }
    set {
     states[A._mangledName] = newValue
    }
   }

   state = initialState

   let values =
    withUnsafeMutablePointer(to: &state.values) { $0 }
   let indices =
    withUnsafeMutablePointer(to: &state.indices) { $0 }

   ModuleIndex.bind(
    base: [A.shared],
    basePointer: values,
    indicesPointer: indices
   )

   let index = initialState.indices[0]

   initialState.mainContext = .cached(index, with: initialState, key: index.key)

   index.step(initialState.recurse)
   initialState.mainContext.callAsFunction()
  } else {
   let context = states[A._mangledName].unsafelyUnwrapped.mainContext
   if context.calledTask != nil {
    context.callAsFunction()
   }
  }
 }

 @inlinable
 static func cacheOrCall<A: StaticModule>(_ moduleType: A.Type, call: Bool) {
  if call {
   Reflection.callIfNeeded(A.self)
  } else {
   Reflection.cacheIfNeeded(A.self)
  }
 }

 @usableFromInline
 @discardableResult
 static func cacheIfNeeded(
  _ module: some Module,
  id: AnyHashable
 ) -> ModuleState {
  if states[id] == nil {
   let initialState = ModuleState()
   unowned var state: ModuleState {
    get { states[id].unsafelyUnwrapped }
    set {
     states[id] = newValue
    }
   }

   state = initialState

   let values =
    withUnsafeMutablePointer(to: &state.values) { $0 }
   let indices =
    withUnsafeMutablePointer(to: &state.indices) { $0 }

   ModuleIndex.bind(
    base: [module],
    basePointer: values,
    indicesPointer: indices
   )

   let index = initialState.indices[0]

   initialState.mainContext = .cached(index, with: initialState, key: index.key)

   index.step(initialState.recurse)

   return initialState
  }
  return states[id].unsafelyUnwrapped
 }

 /// Enables repeated calls from a base module using an id to retain state
 @discardableResult
 @usableFromInline
 static func call(
  _ module: some Module,
  id: AnyHashable
 ) -> UnsafeMutablePointer<any Module> {
  if states[id] == nil {
   let initialState = ModuleState()
   unowned var state: ModuleState {
    get { states[id].unsafelyUnwrapped }
    set {
     states[id] = newValue
    }
   }

   state = initialState

   let values =
    withUnsafeMutablePointer(to: &state.values) { $0 }
   let indices =
    withUnsafeMutablePointer(to: &state.indices) { $0 }

   ModuleIndex.bind(
    base: [module],
    basePointer: values,
    indicesPointer: indices
   )

   let index = initialState.indices[0]

   initialState.mainContext = .cached(index, with: initialState, key: index.key)

   index.step(initialState.recurse)

   ModuleContext.cache[index.key].unsafelyUnwrapped
    .callAsFunction()

   return withUnsafeMutablePointer(to: &index.element) { $0 }
  } else {
   let state = states[id].unsafelyUnwrapped
   let index = state.indices[0]

   state.mainContext.callAsFunction()
   return withUnsafeMutablePointer(to: &index.element) { $0 }
  }
 }

 @inlinable
 static func cacheOrCall(_ module: some Module, id: AnyHashable, call: Bool) {
  if call {
   Reflection.call(module, id: id)
  } else {
   Reflection.cacheIfNeeded(module, id: id)
  }
 }
}
