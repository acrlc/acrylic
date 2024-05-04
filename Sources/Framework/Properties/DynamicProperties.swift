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
<A, Value: Sendable>: ContextualProperty, DynamicProperty
 where A: StaticModule {
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

public extension View {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
 typealias ObservedAlias<A, Value> = _ObservedModuleAliasProperty<A, Value>
  where A: ObservableModule
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
#endif

@propertyWrapper
public struct _StaticModuleAliasProperty
<A: StaticModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty, DynamicProperty {
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

public extension Module {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
}

/* MARK: - Observable Properties */
@propertyWrapper
public struct _ObservedModuleAliasProperty
<A: ObservableModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty, DynamicProperty {
 public var id = A._mangledName.hashValue
 public var context: ModuleContext

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 #if canImport(SwiftUI) || canImport(TokamakDOM)
 @ObservedObject
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
