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
 public var id = AnyHashable(A._mangledName)

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>
 public var context: ModuleContext = .shared

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { A.shared[keyPath: keyPath] }
  nonmutating set {
   A.shared[keyPath: keyPath] = newValue
  }
 }

 #if os(macOS) || os(iOS)
 @inlinable
 public var projectedValue: Binding<Value> {
  Binding<Value>(
   get: { wrappedValue },
   set: { newValue in wrappedValue = newValue }
  )
 }
 #endif
}

public extension View {
 typealias Alias<A, Value> = _StaticModuleAliasProperty<A, Value>
  where A: StaticModule
 typealias ObservedAlias<A, Value> = _ObservedModuleAliasProperty<A, Value>
  where A: ObservableModule
 typealias ContextAlias<A, Value> = _ObservedContextModuleAliasProperty<
  A,
  Value
 >
  where A: ContextModule
}

public extension App {
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

import protocol Core.Infallible
extension ContextProperty where Value: Infallible {
 init(wrappedValue: Value = .defaultValue) {
  self = .constant(wrappedValue)
 }
}
#endif

@propertyWrapper
public struct _StaticModuleAliasProperty
<A: StaticModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty, DynamicProperty {
 public var id = AnyHashable(A._mangledName)
 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 public unowned var context: ModuleContext = .shared

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { A.shared[keyPath: keyPath] }
  nonmutating set { A.shared[keyPath: keyPath] = newValue }
 }

 #if os(macOS) || os(iOS)
 @inlinable
 public var projectedValue: Binding<Value> {
  Binding<Value>(
   get: { wrappedValue },
   set: { newValue in wrappedValue = newValue }
  )
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
  Reflection.cacheOrCall(A.self, call: call)
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
 }

 init(_ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false) {
  Reflection.cacheOrCall(A.self, call: call)
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
 }

 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  Reflection.cacheOrCall(A.self, call: call)
  context = Reflection.states[A._mangledName]!.mainContext
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  Reflection.cacheOrCall(A.self, call: call)
  context = Reflection.states[A._mangledName]!.mainContext
 }
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
 public var id = AnyHashable(A._mangledName)
 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 #if canImport(SwiftUI) || canImport(TokamakDOM)
 @ObservedObject
 var module: A = .shared
 #else
 unowned var module: A = .shared
 #endif

 public var context: ModuleContext = .shared

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { A.shared[keyPath: keyPath] }
  nonmutating set { A.shared[keyPath: keyPath] = newValue }
 }

 // FIXME: context properties to update context here (from projectedValue)
 #if os(macOS) || os(iOS)
 @inlinable
 public var projectedValue: Binding<Value> {
  Binding<Value>(
   get: { wrappedValue },
   set: { newValue in wrappedValue = newValue }
  )
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
  Reflection.cacheOrCall(A.self, call: call)
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
 }

 init(_ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false) {
  Reflection.cacheOrCall(A.self, call: call)
  self.keyPath = keyPath.appending(path: \.wrappedValue)
  let wrapper = A.shared[keyPath: keyPath]
  context = wrapper.context
  id = wrapper.id
 }

 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  self.keyPath = keyPath
  Reflection.cacheOrCall(A.self, call: call)
  context = Reflection.states[A._mangledName]!.mainContext
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false) where Value == A {
  keyPath = \A.self
  Reflection.cacheOrCall(A.self, call: call)
  context = Reflection.states[A._mangledName]!.mainContext
 }
}

#if os(WASI) && canImport(TokamakDOM)
extension _ObservedModuleAliasProperty: ObservedProperty {
 public var objectWillChange: AnyPublisher<(), Never> {
  context.objectWillChange.map { _ in }.eraseToAnyPublisher()
 }
}
#endif

@propertyWrapper
public struct _ObservedContextModuleAliasProperty
<A: ContextModule, Value: Sendable>:
 @unchecked Sendable, ContextualProperty, DynamicProperty {
 public var id = AnyHashable(A._mangledName)
 #if canImport(SwiftUI) || canImport(TokamakDOM)
 @ObservedObject
 public var context: ModuleContext = .shared
 #else
 public unowned var context: ModuleContext = .shared
 #endif

 @usableFromInline
 let keyPath: WritableKeyPath<A, Value>

 @usableFromInline
 var module: A {
  get { context.state.values[0] as! A }
  nonmutating set { context.state.values[0] = newValue }
 }

 @inlinable
 public var wrappedValue: Value {
  nonmutating get { module[keyPath: keyPath] }
  nonmutating set { module[keyPath: keyPath] = newValue }
 }

 // FIXME: context properties to update context here (from projectedValue)
 #if os(macOS) || os(iOS)
 @inlinable
 public var projectedValue: Binding<Value> {
  Binding<Value>(
   get: { wrappedValue },
   set: { newValue in wrappedValue = newValue }
  )
 }
 #endif
}

@Reflection(unsafe)
public extension _ObservedContextModuleAliasProperty {
// init(
//  wrappedValue: Value,
//  _ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false
// ) {
//  self.keyPath = keyPath.appending(path: \.wrappedValue)
//  Reflection.cacheOrCall(A(), id: A._mangledName, call: call)
//  let wrapper = (Self.index.element as! A)[keyPath: keyPath]
//  context = wrapper.context
//  id = wrapper.id
// }
//
// init(_ keyPath: KeyPath<A, ContextProperty<Value>>, _ call: Bool = false) {
//  Reflection.cacheOrCall(A(), id: A._mangledName, call: call)
//  self.keyPath = keyPath.appending(path: \.wrappedValue)
//  let wrapper = (Self.index.element as! A)[keyPath: keyPath]
//  context = wrapper.context
//  id = wrapper.id
// }

 @_disfavoredOverload
 init(_ keyPath: WritableKeyPath<A, Value>, _ call: Bool = false) {
  Reflection.cacheOrCall(A(), id: A._mangledName, call: call)
  //self.context = Reflection.states[A._mangledName]!.mainContext
  self.keyPath = keyPath
 }

 @_disfavoredOverload
 init(_ type: A.Type, _ call: Bool = false) where Value == A {
  Reflection.cacheOrCall(A(), id: A._mangledName, call: call)
  //self.context = Reflection.states[A._mangledName]!.mainContext
  keyPath = \A.self
 }
}

#if os(WASI) && canImport(TokamakDOM)
extension _ObservedModuleContextAliasProperty: ObservedProperty {
 public var objectWillChange: AnyPublisher<(), Never> {
  context.objectWillChange.map { _ in }.eraseToAnyPublisher()
 }
}
#endif
