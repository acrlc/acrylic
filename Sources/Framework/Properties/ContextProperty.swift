import Foundation

#if canImport(SwiftUI)
@_exported import protocol SwiftUI.DynamicProperty
#else
/// An interface for a stored variable that updates an external property of a
/// module.
///
/// The module gives values to these properties prior to recomputing the
/// modules's ``Module/void-swift.property``.
@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public protocol DynamicProperty {
 /// Updates the underlying value of the stored value.
 ///
 /// This is called before updating to ensure it's module has the most recent
 /// value.
 mutating func update()
}

@available(iOS 13.0, macOS 10.15, tvOS 13.0, watchOS 6.0, *)
public extension DynamicProperty {
 /// Updates the underlying value of the stored value.
 /// This is called before updating to ensure it's structure has the most recent
 /// value.
 mutating func update() {}
}

#endif

@_spi(ModuleReflection)
public typealias DynamicProperties = [
 (label: String, keyPath: AnyKeyPath, property: any DynamicProperty)
]

extension [(label: String, keyPath: AnyKeyPath, property: any DynamicProperty)]:
 @unchecked Sendable {}
extension AnyKeyPath: @unchecked Sendable {}

// MARK: - Context Properties
public protocol ContextualProperty: Identifiable, DynamicProperty, Sendable {
 nonisolated(unsafe) var id: Int { @Sendable get set }
 nonisolated(unsafe) var context: ModuleContext { get set }
}

// MARK: - ContextProperty
@dynamicMemberLookup
@propertyWrapper
public struct
ContextProperty<Value: Sendable>: @unchecked Sendable, ContextualProperty {
 public var id = UUID().hashValue
 public unowned var context: ModuleContext = .unknown {
  willSet {
   initialize(from: context, to: newValue)
  }
 }

 @usableFromInline
 var initialValue: Any?

 public var wrappedValue: Value {
  get {
   context.values.withReaderLock {
    $0[id] as? Value ?? initialValue as! Value
   }
  }
  nonmutating set {
   context.values.withWriterLockVoid { $0[self.id] = newValue }
  }
 }

 @inlinable
 public var projectedValue: Self { self }

 public subscript<A>(
  dynamicMember keyPath: WritableKeyPath<Value, A>
 ) -> ContextProperty<A> {
  get { .constant(wrappedValue[keyPath: keyPath]) }
  nonmutating set {
   wrappedValue[keyPath: keyPath] = newValue.wrappedValue
  }
 }

 @inlinable
 public init(wrappedValue: Value) { initialValue = wrappedValue }

 public init() where Value: ExpressibleByNilLiteral {
  initialValue = Value(nilLiteral: ())
 }
 
 @_disfavoredOverload
 public init() {}

 @_disfavoredOverload
 @inlinable
 public init() where Value: Infallible { initialValue = Value.defaultValue }

 @inlinable
 public static func constant(_ value: Value) -> Self {
  Self(wrappedValue: value)
 }
}

public extension ContextProperty {
 func update() {
  Task { @Reflection in
   guard context.state < .terminal else { return }
   try await context.update()
  }
 }

 mutating func initialize(
  from oldContext: ModuleContext, to newContext: ModuleContext
 ) {
  assert(
   oldContext != newContext,
   "previous context cannot be assigned to property"
  )

  let id = id
  if let value = oldContext.values.withReaderLock({ $0[id] }) {
   oldContext.values.withWriterLockVoid {
    $0.removeValue(forKey: id)
    newContext.values.withWriterLockVoid {
     $0[id] = value
     initialValue = nil
    }
   }
  } else {
   newContext.values.withWriterLockVoid {
    $0[id] = initialValue
    initialValue = nil
   }
  }
 }
}

public extension ContextProperty {
 func callAsFunction() async throws {
  assert(
   context != .unknown,
   "cannot called shared context, states must be initialized before handling"
  )
  try await context.callAsFunction()
 }

 @discardableResult
 func callResult<A>(
  _ body: @escaping () throws -> A
 ) rethrows -> A {
  assert(
   context != .unknown,
   "cannot called shared context, states must be initialized before handling"
  )
  defer { Task { try await self.context.callAsFunction() } }
  return try body()
 }

 func callAsFunction(
  _ newValue: @escaping @autoclosure () -> Value = ()
 ) async throws {
  assert(
   context != .unknown,
   "cannot called shared context, states must be initialized before handling"
  )
  wrappedValue = newValue()
  try await context.callAsFunction()
 }
}

#if canImport(SwiftUI) || canImport(TokamakDOM)
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#else
#error("Cannot import Combine framework")
#endif

@MainActor
public extension ContextProperty {
 @discardableResult
 func state<A>(
  _ value: @escaping (inout Value) throws -> A
 ) rethrows -> A {
  defer { context.objectWillChange.send() }
  return try value(&wrappedValue)
 }

 @discardableResult
 func callState<A>(
  _ value: @escaping (inout Value) throws -> A
 ) rethrows -> A {
  defer {
   Task {
    try await self.callAsFunction()
   }
   context.objectWillChange.send()
  }
  return try value(&wrappedValue)
 }

 func state(_ newValue: Value) {
  wrappedValue = newValue
  context.objectWillChange.send()
 }

 func callState(_ newValue: Value) {
  wrappedValue = newValue
  Task {
   try await callAsFunction()
  }
  context.objectWillChange.send()
 }

 func updateState() {
  context.objectWillChange.send()
 }
}
#endif

public extension ContextProperty {
 @inline(__always)
 func update(
  _ newValue: @escaping @autoclosure () -> Value = ()
 ) async throws {
  wrappedValue = newValue()
  try await context.update()
 }
}

public extension Module {
 typealias Context<Value> = ContextProperty<Value>
}

extension ContextProperty: CustomStringConvertible {
 public var description: String {
  String(describing: wrappedValue).readable
 }
}

extension ContextProperty: Codable where Value: Codable {
 public init(from decoder: Decoder) throws {
  let container = try decoder.singleValueContainer()
  self.initialValue = try container.decode(Value.self)
 }

 public func encode(to encoder: Encoder) throws {
  var container = encoder.singleValueContainer()
  try container.encode(self.wrappedValue)
 }
}

// MARK: - Pesistent Implementation
#if canImport(Persistence)
import Persistence

@dynamicMemberLookup
@propertyWrapper
public struct DefaultsContextProperty<Defaults, Key, Value>:
 ContextualProperty where Defaults: CustomUserDefaults, Key: UserDefaultsKey {
 public subscript<A>(
  dynamicMember keyPath: WritableKeyPath<Value, A>
 ) -> ContextProperty<A> {
  get { .constant(wrappedValue[keyPath: keyPath]) }
  nonmutating set {
   wrappedValue[keyPath: keyPath] = newValue.wrappedValue
  }
 }

 @inline(__always)
 @usableFromInline
 var defaults: DefaultsProperty<Defaults, Key, Value>
 @inline(__always)
 @usableFromInline
 var wrapped: ContextProperty<Value>

 @_transparent
 public var id: Int { get { wrapped.id } set { wrapped.id = newValue } }

 @_transparent
 public var context: ModuleContext {
  get { wrapped.context }
  set { wrapped.context = newValue }
 }

 @_transparent
 public var wrappedValue: Value {
  get { defaults.wrappedValue }
  nonmutating set {
   wrapped.wrappedValue = newValue
   defaults.wrappedValue = newValue
  }
 }

 public var projectedValue: ContextProperty<Value> {
  get { .constant(wrappedValue) }
  nonmutating set {
   wrapped.wrappedValue = newValue.wrappedValue
   defaults.wrappedValue = newValue.wrappedValue
  }
 }

 public init(_ key: Key)
  where Defaults == CustomUserDefaults, Value == Key.Value {
  self.defaults = DefaultsProperty(key)
  self.wrapped = .constant(defaults.wrappedValue)
 }

 public init(
  _ key: Key, _ keyPath: WritableKeyPath<Key.Value, Value>
 ) where Defaults == CustomUserDefaults {
  self.defaults = DefaultsProperty(key, keyPath)
  self.wrapped = .constant(defaults.wrappedValue)
 }
}

@dynamicMemberLookup
@propertyWrapper
public struct StandardDefaultsContextProperty<Defaults, Key, Value>:
 ContextualProperty
 where Defaults: CustomUserDefaults, Key: StandardUserDefaultsKey {
 public subscript<A>(
  dynamicMember keyPath: WritableKeyPath<Value, A>
 ) -> ContextProperty<A> {
  get { .constant(wrappedValue[keyPath: keyPath]) }
  nonmutating set {
   wrappedValue[keyPath: keyPath] = newValue.wrappedValue
  }
 }

 @inline(__always)
 @usableFromInline
 var defaults: DefaultsProperty<Defaults, Key, Value>
 @inline(__always)
 @usableFromInline
 var wrapped: ContextProperty<Value>

 @_transparent
 public var id: Int { get { wrapped.id } set { wrapped.id = newValue } }

 @_transparent
 public var context: ModuleContext {
  get { wrapped.context }
  set { wrapped.context = newValue }
 }

 @_transparent
 public var wrappedValue: Value {
  get { defaults.wrappedValue }
  nonmutating set {
   wrapped.wrappedValue = newValue
   defaults.wrappedValue = newValue
  }
 }

 public var projectedValue: ContextProperty<Value> {
  get { .constant(wrappedValue) }
  nonmutating set {
   wrapped.wrappedValue = newValue.wrappedValue
   defaults.wrappedValue = newValue.wrappedValue
  }
 }

 public init(_ key: Key)
  where Defaults == CustomUserDefaults, Value == Key.Value {
  self.defaults = DefaultsProperty(key)
  self.wrapped = .constant(defaults.wrappedValue)
 }

 public init(
  _ key: Key, _ keyPath: WritableKeyPath<Key.Value, Value>
 ) where Defaults == CustomUserDefaults {
  self.defaults = DefaultsProperty(key, keyPath)
  self.wrapped = .constant(defaults.wrappedValue)
 }
}

public extension Module {
 typealias DefaultContext<Key, Value> =
  DefaultsContextProperty<CustomUserDefaults, Key, Value>
   where Key: UserDefaultsKey
 typealias StandardDefaultContext<Key, Value> =
  StandardDefaultsContextProperty<CustomUserDefaults, Key, Value>
   where Key: StandardUserDefaultsKey
}
#endif
