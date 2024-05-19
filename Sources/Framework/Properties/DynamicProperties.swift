#if canImport(SwiftUI) || canImport(TokamakDOM)
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#else
#error("Cannot import Combine framework")
#endif

#if os(WASI)
import TokamakCore
import TokamakDOM
extension ModuleContext: OpenCombine.ObservableObject {}
#elseif canImport(SwiftUI)
import SwiftUI
extension ModuleContext: Combine.ObservableObject {}
#endif

@propertyWrapper
public struct _DynamicContextBindingProperty
<A, Value: Sendable>: ContextualProperty where A: StaticModule {
 public var id = A._mangledName.hashValue

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>
 public unowned var context: ModuleContext = .unknown

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { A.shared[keyPath: keyPath] }
  nonmutating set {
   A.shared[keyPath: keyPath] = newValue
  }
 }

 #if os(macOS) || os(iOS)
 public var animation: Animation?
 @inline(__always)
 public var projectedValue: Binding<Value> {
  if let animation {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in withAnimation(animation) { wrappedValue = newValue } }
   )
  } else {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in wrappedValue = newValue }
   )
  }
 }
 #endif
}

@propertyWrapper
public struct _ObservedContextAliasProperty
<A: ContextModule, Value: Sendable>:
 @unchecked Sendable, DynamicProperty {
 public var id = A._mangledName.hashValue

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 #if canImport(SwiftUI) || canImport(TokamakDOM)
 @StateObject
 public var context: ModuleContext = .unknown
 #else
 public unowned var context: ModuleContext = .unknown
 #endif

 @Reflection(unsafe)
 @usableFromInline
 var module: A {
  nonmutating get {
   Reflection.cacheIfNeeded(
    id: A._mangledName, module: { A() }, stateType: ModuleState.self
   ).context.index.element as! A
  }
  nonmutating set {
   Reflection.cacheIfNeeded(
    id: A._mangledName,
    module: { A() },
    stateType: ModuleState.self
   ).context.index.element = newValue
  }
 }

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set { module[keyPath: keyPath] = newValue }
 }

 // FIXME: context properties to update context here (from projectedValue)
 #if os(macOS) || os(iOS)
 var animation: Animation?
 public var projectedValue: Binding<Value> {
  if let animation {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in
     withAnimation(animation) { wrappedValue = newValue }
    }
   )
  } else {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in wrappedValue = newValue }
   )
  }
 }
 #endif
}

@Reflection(unsafe)
public extension _ObservedContextAliasProperty {
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  )

  let module = Reflection.states[id]!.context.index.element as! A
  let wrapper = module[keyPath: keyPath]

  _context = .init(wrappedValue: wrapper.context)
  id = wrapper.id
 }

 init(_ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false) {
  Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  )

  self.keyPath = keyPath.appending(path: \.wrappedValue)

  let module = Reflection.states[id]!.context.index.element as! A
  let wrapper = module[keyPath: keyPath]

  _context = .init(wrappedValue: wrapper.context)
  id = wrapper.id
 }

 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  _context = .init(
   wrappedValue:
   Reflection.cacheOrCall(
    id: A._mangledName,
    module: A(),
    stateType: ModuleState.self,
    call: call
   ).context
  )
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  _context = .init(
   wrappedValue:
   Reflection.cacheOrCall(
    id: A._mangledName,
    module: A(),
    stateType: ModuleState.self,
    call: call
   ).context
  )
 }

 #if os(macOS) || os(iOS)
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  )

  let module = Reflection.states[id]!.context.index.element as! A
  let wrapper = module[keyPath: keyPath]

  _context = .init(wrappedValue: wrapper.context)
  id = wrapper.id
 }

 init(
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  )

  self.keyPath = keyPath.appending(path: \.wrappedValue)

  let module = Reflection.states[id]!.context.index.element as! A
  let wrapper = module[keyPath: keyPath]

  _context = .init(wrappedValue: wrapper.context)
  id = wrapper.id
 }

 @_disfavoredOverload
 init(
  _ keyPath: WritableKeyPath<A, Value>,
  _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath
  _context = .init(
   wrappedValue:
   Reflection.cacheOrCall(
    id: A._mangledName,
    module: A(),
    stateType: ModuleState.self,
    call: call
   ).context
  )
  self.animation = animation
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false, animation: Animation)
  where Value == A {
  keyPath = \A.self
  _context = .init(
   wrappedValue:
   Reflection.cacheOrCall(
    id: A._mangledName,
    module: A(),
    stateType: ModuleState.self,
    call: call
   ).context
  )
  self.animation = animation
 }

 #endif
}

public extension View {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
 typealias ObservedAlias<A, Value> = _ObservedModuleAliasProperty<A, Value>
  where A: ObservableModule
 typealias ContextAlias<A, Value> = _ObservedContextAliasProperty<A, Value>
  where A: ContextModule
 typealias StaticObservedAlias<A, Value> = _StaticObservedModuleAliasProperty<
  A,
  Value
 >
  where A: StaticModule
}

public extension App {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
 typealias ObservedAlias<A, Value> = _ObservedModuleAliasProperty<A, Value>
  where A: ObservableModule
}

public extension Scene {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
 typealias ObservedAlias<A, Value> = _ObservedModuleAliasProperty<A, Value>
  where A: ObservableModule
}

public extension Commands {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
 typealias ObservedAlias<A, Value> = _ObservedModuleAliasProperty<A, Value>
  where A: ObservableModule
}

public extension ToolbarContent {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
 typealias ObservedAlias<A, Value> = _ObservedModuleAliasProperty<A, Value>
  where A: ObservableModule
}

/* MARK: - Observable Properties */
@propertyWrapper
public struct _ObservedModuleAliasProperty
<A: ObservableModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty {
 public var id = A._mangledName.hashValue
 public var context: ModuleContext

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 #if canImport(SwiftUI) || canImport(TokamakDOM)
 @StateObject
 var module: A = .shared
 #else
 unowned var module: A = .shared
 #endif

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { A.shared[keyPath: keyPath] }
  nonmutating set { A.shared[keyPath: keyPath] = newValue }
 }

 // FIXME: context properties to update context here (from projectedValue)
 #if os(macOS) || os(iOS)
 var animation: Animation?
 public var projectedValue: Binding<Value> {
  if let animation {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in
     withAnimation(animation) { wrappedValue = newValue }
    }
   )
  } else {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in wrappedValue = newValue }
   )
  }
 }
 #endif
}

@Reflection(unsafe)
public extension _ObservedModuleAliasProperty {
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
 }

 init(_ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false) {
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
 }

 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
 }

 #if os(macOS) || os(iOS)
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
  self.animation = animation
 }

 init(
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
  self.animation = animation
 }

 @_disfavoredOverload
 init(
  _ keyPath: WritableKeyPath<A, Value>,
  _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
  self.animation = animation
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false, animation: Animation)
  where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
  self.animation = animation
 }

 #endif
}

#if os(WASI) && canImport(TokamakDOM)
extension _ObservedModuleAliasProperty: ObservedProperty {
 public var objectWillChange: AnyPublisher<(), Never> {
  context.objectWillChange.map { _ in }.eraseToAnyPublisher()
 }
}
#endif


@propertyWrapper
public struct _StaticObservedModuleAliasProperty
<A: StaticModule, Value: Sendable>:
 @unchecked Sendable, DynamicProperty {
 public var id = A._mangledName.hashValue

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 #if canImport(SwiftUI) || canImport(TokamakDOM)
 @StateObject
 public var context: ModuleContext = .unknown
 #else
 public unowned var context: ModuleContext = .unknown
 #endif

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { A.shared[keyPath: keyPath] }
  nonmutating set { A.shared[keyPath: keyPath] = newValue }
 }

 // FIXME: context properties to update context here (from projectedValue)
 #if os(macOS) || os(iOS)
 var animation: Animation?
 public var projectedValue: Binding<Value> {
  if let animation {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in
     withAnimation(animation) { wrappedValue = newValue }
    }
   )
  } else {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in wrappedValue = newValue }
   )
  }
 }
 #endif
}

@Reflection(unsafe)
public extension _StaticObservedModuleAliasProperty {
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  let wrapper = A.shared[keyPath: keyPath]
  _context = .init(
   wrappedValue:
   wrapper.context
  )
  id = wrapper.id
 }

 init(_ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false) {
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  let wrapper = A.shared[keyPath: keyPath]
  _context = .init(
   wrappedValue:
   wrapper.context
  )
  id = wrapper.id
 }

 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  _context = .init(
   wrappedValue:
   Reflection.cacheOrCall(
    moduleType: A.self,
    stateType: ModuleState.self,
    call: call
   ).context
  )
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  _context = .init(
   wrappedValue:
   Reflection.cacheOrCall(
    moduleType: A.self,
    stateType: ModuleState.self,
    call: call
   ).context
  )
 }

 #if os(macOS) || os(iOS)
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  let wrapper = A.shared[keyPath: keyPath]
  _context = .init(
   wrappedValue:
   wrapper.context
  )
  id = wrapper.id
  self.animation = animation
 }

 init(
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  let wrapper = A.shared[keyPath: keyPath]
  _context = .init(
   wrappedValue:
   wrapper.context
  )
  id = wrapper.id
  self.animation = animation
 }

 @_disfavoredOverload
 init(
  _ keyPath: WritableKeyPath<A, Value>,
  _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath
  _context = .init(
   wrappedValue:
   Reflection.cacheOrCall(
    moduleType: A.self,
    stateType: ModuleState.self,
    call: call
   ).context
  )
  self.animation = animation
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false, animation: Animation)
  where Value == A {
  keyPath = \A.self
  _context = .init(
   wrappedValue:
   Reflection.cacheOrCall(
    moduleType: A.self,
    stateType: ModuleState.self,
    call: call
   ).context
  )
  self.animation = animation
 }
 #endif
}
#endif

/* MARK: - Module Properties */
@propertyWrapper
public struct _StaticModuleAliasProperty
<A: StaticModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty {
 public var id = A._mangledName.hashValue
 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>
 
 public unowned var context: ModuleContext = .unknown
 
 @inlinable
 public var wrappedValue: Value {
  nonmutating get { A.shared[keyPath: keyPath] }
  nonmutating set { A.shared[keyPath: keyPath] = newValue }
 }
 
#if os(macOS) || os(iOS)
 var animation: Animation?
 public var projectedValue: Binding<Value> {
  if let animation {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in
     withAnimation(animation) { wrappedValue = newValue }
    }
   )
  } else {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in wrappedValue = newValue }
   )
  }
 }
#endif
}

@Reflection(unsafe)
public extension _StaticModuleAliasProperty {
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
 }
 
 init(_ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false) {
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
 }
 
 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
 }
 
 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
 }
 
#if os(macOS) || os(iOS)
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
  self.animation = animation
 }
 
 init(
  _ keyPath: KeyPath<A, ContextProperty<Value>>,
  _ call: Bool = false,
  animation: Animation
 ) {
  Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  )
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
  self.animation = animation
 }
 
 @_disfavoredOverload
 init(
  _ keyPath: WritableKeyPath<A, Value>,
  _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
  self.animation = animation
 }
 
 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false, animation: Animation)
 where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
  self.animation = animation
 }
#endif
}

@propertyWrapper
public struct _ContextAliasProperty
<A: ContextModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty {
 public var id = A._mangledName.hashValue
 
 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>
 
 public unowned var context: ModuleContext = .unknown
 
 @Reflection(unsafe)
 @usableFromInline
 var module: A {
  nonmutating get {
   Reflection.cacheIfNeeded(
    id: A._mangledName, module: { A() }, stateType: ModuleState.self
   ).context.index.element as! A
  }
  nonmutating set {
   Reflection.cacheIfNeeded(
    id: A._mangledName,
    module: { A() },
    stateType: ModuleState.self
   ).context.index.element = newValue
  }
 }
 
 @inlinable
 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set { module[keyPath: keyPath] = newValue }
 }
 
 // FIXME: context properties to update context here (from projectedValue)
#if os(macOS) || os(iOS)
 var animation: Animation?
 public var projectedValue: Binding<Value> {
  if let animation {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in
     withAnimation(animation) { wrappedValue = newValue }
    }
   )
  } else {
   Binding<Value>(
    get: { wrappedValue },
    set: { newValue in wrappedValue = newValue }
   )
  }
 }
#endif
}

@Reflection(unsafe)
public extension _ContextAliasProperty {
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  )
  
  let module = Reflection.states[id]!.context.index.element as! A
  let wrapper = module[keyPath: keyPath]
  
  context = wrapper.context
  id = wrapper.id
 }
 
 init(_ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false) {
  Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  )
  
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  
  let module = Reflection.states[id]!.context.index.element as! A
  let wrapper = module[keyPath: keyPath]
  
  context = wrapper.context
  id = wrapper.id
 }
 
 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  context = Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  ).context
 }
 
 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  ).context
 }
 
#if os(macOS) || os(iOS)
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  )
  
  let module = Reflection.states[id]!.context.index.element as! A
  let wrapper = module[keyPath: keyPath]
  
  context = wrapper.context
  id = wrapper.id
 }
 
 init(
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation: Animation
 ) {
  Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  )
  
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  
  let module = Reflection.states[id]!.context.index.element as! A
  let wrapper = module[keyPath: keyPath]
  
  context = wrapper.context
  id = wrapper.id
 }
 
 @_disfavoredOverload
 init(
  _ keyPath: WritableKeyPath<A, Value>,
  _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath
  context = Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  ).context
  self.animation = animation
 }
 
 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false, animation: Animation)
 where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  ).context
  self.animation = animation
 }
 
#endif
}

public extension Module {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
 where A: StaticModule
 typealias ContextAlias<A, Value> = _ContextAliasProperty<A, Value>
 where A: ContextModule
}



