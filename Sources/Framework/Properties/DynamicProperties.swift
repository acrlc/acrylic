#if canImport(SwiftUI) || canImport(TokamakCore)
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#else
#error("Cannot import Combine framework")
#endif

#if os(WASI)
import TokamakCore

extension ModuleContext: OpenCombine.ObservableObject {}
#else
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

 #if canImport(SwiftUI)
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
 @unchecked Sendable, DynamicProperty
{
 public var id = A._mangledName.hashValue

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 #if canImport(SwiftUI) || canImport(TokamakCore)
 @ObservedObject
 public var context: ModuleContext = .unknown
 #else
 public unowned var context: ModuleContext = .unknown
 #endif

 @usableFromInline
 var module: A {
  nonmutating get { context.index.element as! A }
  nonmutating set { context.index.element = newValue }
 }

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set { module[keyPath: keyPath] = newValue }
 }

 // FIXME: context properties to update context here (from projectedValue)
 #if canImport(SwiftUI)
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

#if os(WASI)
extension _ObservedContextAliasProperty: ObservedProperty {
 public var objectWillChange: AnyPublisher<Void, Never> {
  context.objectWillChange.map { _ in }.eraseToAnyPublisher()
 }
}
#endif

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

  _context = ObservedObject(wrappedValue: wrapper.context)
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

  _context = ObservedObject(wrappedValue: wrapper.context)
  id = wrapper.id
 }

 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  _context = ObservedObject(
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
 init(_: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  _context = ObservedObject(
   wrappedValue:
   Reflection.cacheOrCall(
    id: A._mangledName,
    module: A(),
    stateType: ModuleState.self,
    call: call
   ).context
  )
 }

 #if canImport(SwiftUI)
 init(
  wrappedValue: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation _: Animation
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

  _context = ObservedObject(wrappedValue: wrapper.context)
  id = wrapper.id
 }

 init(
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation _: Animation
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

  _context = ObservedObject(wrappedValue: wrapper.context)
  id = wrapper.id
 }

 @_disfavoredOverload
 init(
  _ keyPath: WritableKeyPath<A, Value>,
  _ call: Bool = false,
  animation: Animation
 ) {
  self.keyPath = keyPath
  _context = ObservedObject(
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
 init(_: A.Type, _ call: Bool = false, animation: Animation)
  where Value == A
 {
  keyPath = \A.self
  _context = ObservedObject(
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
 typealias ContextAlias<A, Value> = _ObservedContextAliasProperty<A, Value>
  where A: ContextModule
 typealias StaticObservedAlias<A, Value> = _StaticObservedModuleAliasProperty<
  A,
  Value
 >
  where A: StaticModule
}

public extension Scene {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
 typealias ObservedAlias<A, Value> = _ObservedModuleAliasProperty<A, Value>
  where A: ObservableModule
}

#if canImport(SwiftUI)
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
#endif

/* MARK: - Observable Properties */
@propertyWrapper
public struct _ObservedModuleAliasProperty
<A: ObservableModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty
{
 public var id = A._mangledName.hashValue
 public var context: ModuleContext

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>
 #if canImport(SwiftUI) || canImport(TokamakCore)
 @ObservedObject
 var module: A = .shared
 public var wrappedValue: Value {
  nonmutating get {
   module[keyPath: keyPath]
  }
  nonmutating set {
   A.shared[keyPath: keyPath] = newValue
  }
 }
 #else
 @usableFromInline
 var module: A {
  nonmutating get { context.index.element as! A }
  nonmutating set { context.index.element = newValue }
 }

 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set { module[keyPath: keyPath] = newValue }
 }
 #endif

 // FIXME: context properties to update context here (from projectedValue)
 #if canImport(SwiftUI)
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
 #else
 public var projectedValue: Binding<Value> {
  Binding<Value>(
   get: { wrappedValue },
   set: { newValue in wrappedValue = newValue }
  )
 }
 #endif
}

public extension _ObservedModuleAliasProperty {
 init(
  wrappedValue _: Value,
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
 init(_: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
 }

 #if os(macOS) || os(iOS)
 init(
  wrappedValue _: Value,
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
 init(_: A.Type, _ call: Bool = false, animation: Animation)
  where Value == A
 {
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

#if os(WASI)
extension _ObservedModuleAliasProperty: ObservedProperty {
 public var objectWillChange: AnyPublisher<Void, Never> {
  A.shared.objectWillChange.map { _ in }.eraseToAnyPublisher()
 }
}
#endif

@propertyWrapper
public struct _StaticObservedModuleAliasProperty
<A: StaticModule, Value: Sendable>:
 @unchecked Sendable, DynamicProperty
{
 public var id = A._mangledName.hashValue

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 @usableFromInline
 var module: A {
  nonmutating get { context.index.element as! A }
  nonmutating set { context.index.element = newValue }
 }

 #if canImport(SwiftUI) || canImport(TokamakCore)
 @ObservedObject
 public var context: ModuleContext = .unknown

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set {
   module[keyPath: keyPath] = newValue
  }
 }
 #else
 public unowned var context: ModuleContext = .unknown

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set { module[keyPath: keyPath] = newValue }
 }
 #endif

 // FIXME: context properties to update context here (from projectedValue)
 #if canImport(SwiftUI)
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
  _context = ObservedObject(
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
  _context = ObservedObject(
   wrappedValue:
   wrapper.context
  )
  id = wrapper.id
 }

 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  _context = ObservedObject(
   wrappedValue:
   Reflection.cacheOrCall(
    moduleType: A.self,
    stateType: ModuleState.self,
    call: call
   ).context
  )
 }

 @_disfavoredOverload
 init(_: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  _context = ObservedObject(
   wrappedValue:
   Reflection.cacheOrCall(
    moduleType: A.self,
    stateType: ModuleState.self,
    call: call
   ).context
  )
 }

 #if canImport(SwiftUI)
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
  _context = ObservedObject(
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
  _context = ObservedObject(
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
  _context = ObservedObject(
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
 init(_: A.Type, _ call: Bool = false, animation: Animation)
  where Value == A
 {
  keyPath = \A.self
  _context = ObservedObject(
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

#if os(WASI)
extension _StaticObservedModuleAliasProperty: ObservedProperty {
 public var objectWillChange: AnyPublisher<Void, Never> {
  context.objectWillChange.map { _ in }.eraseToAnyPublisher()
 }
}
#endif
#endif

/* MARK: - Module Properties */
@propertyWrapper
public struct _StaticModuleAliasProperty
<A: StaticModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty
{
 public var id = A._mangledName.hashValue
 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 public unowned var context: ModuleContext = .unknown

 @usableFromInline
 var module: A {
  nonmutating get { context.index.element as! A }
  nonmutating set { context.index.element = newValue }
 }

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set { module[keyPath: keyPath] = newValue }
 }

 #if canImport(SwiftUI)
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

@Reflection
public extension _StaticModuleAliasProperty {
 init(
  wrappedValue _: Value,
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
 init(_: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   moduleType: A.self,
   stateType: ModuleState.self,
   call: call
  ).context
 }

 #if canImport(SwiftUI)
 init(
  wrappedValue _: Value,
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
 init(_: A.Type, _ call: Bool = false, animation: Animation)
  where Value == A
 {
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
 @unchecked Sendable, ContextualProperty
{
 public var id = A._mangledName.hashValue

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 public unowned var context: ModuleContext = .unknown

 @usableFromInline
 var module: A {
  nonmutating get { context.index.element as! A }
  nonmutating set { context.index.element = newValue }
 }

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set { module[keyPath: keyPath] = newValue }
 }

 // FIXME: context properties to update context here (from projectedValue)
 #if canImport(SwiftUI)
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

@Reflection
public extension _ContextAliasProperty {
 init(
  wrappedValue _: Value,
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
 init(_: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  context = Reflection.cacheOrCall(
   id: A._mangledName,
   module: A(),
   stateType: ModuleState.self,
   call: call
  ).context
 }

 #if canImport(SwiftUI)
 init(
  wrappedValue _: Value,
  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false,
  animation _: Animation
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
  animation _: Animation
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
 init(_: A.Type, _ call: Bool = false, animation: Animation)
  where Value == A
 {
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
