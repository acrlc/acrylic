import Foundation
import os

#if canImport(SwiftUI)
import protocol SwiftUI.DynamicProperty
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

public protocol ContextualProperty: DynamicProperty {
 var id: AnyHashable { get set }
 var context: ModuleContext { get }
 @inlinable
 mutating func initialize()
 @inlinable
 mutating func initialize(with context: ModuleContext)
}

public extension ContextualProperty {
 @_disfavoredOverload
 mutating func initialize() {}
 @_disfavoredOverload
 mutating func initialize(with context: ModuleContext) {}
 @inlinable
 func move(from previous: ModuleContext, to context: ModuleContext) {
  assert(previous != context)
  if previous != context {
   context.values.withLockUnchecked { values in
    let id = self.id
    if values[id] != nil {
     _ = previous.values.withLockUnchecked { $0.removeValue(forKey: id) }
    }
   }
  }
 }
}

@propertyWrapper
public struct
ContextProperty<Value: Sendable>: @unchecked Sendable, ContextualProperty {
 public var id = AnyHashable(UUID())
 public unowned var context: ModuleContext = .shared {
  didSet { move(from: oldValue, to: context) }
 }

 @usableFromInline
 var initialValue: Value?

 @inlinable
 public mutating func initialize() {
  if let initialValue {
   let id = id
   context.values.withLockUnchecked { values in
    if values.keys.contains(id) {
     values[id] = initialValue
     self.initialValue = nil
    }
   }
  }
 }

 @inlinable
 public mutating func initialize(with context: ModuleContext) {
  if let initialValue {
   context.values.withLockUnchecked { values in
    let id = id
    if values.keys.contains(id) {
     values[id] = initialValue
     self.initialValue = nil
    }
   }
  }
  self.context = context
 }

 @inlinable
 public var wrappedValue: Value {
  get {
   context.values.withLockUnchecked {
    if let value = $0[id] as? Value {
     return value
    } else
    if let optional = $0[id] as? Value?, let value = optional {
     return value
    } else {
     precondition(
      initialValue != nil,
      "set \(Self.self) within an initializer or on the property"
     )
     return initialValue.unsafelyUnwrapped
    }
   }
  }
  nonmutating set {
   context.values.withLockUnchecked { $0[self.id] = newValue }
  }
 }

 public init() {}
 @inlinable
 public var projectedValue: Self { self }
}

public extension ContextProperty {
 @inlinable
 init(wrappedValue: Value) { initialValue = wrappedValue }

 @inlinable
 init() where Value: Infallible { initialValue = .defaultValue }

 @_disfavoredOverload
 @inlinable
 init() where Value: ExpressibleByNilLiteral {
  initialValue = nil
 }

 @inlinable
 static func constant(_ value: Value) -> Self {
  self.init(wrappedValue: value)
 }
}

public extension ContextProperty {
 func callAsFunction() {
  precondition(
   context != .shared,
   "cannot called shared context, states must be initialized before handling"
  )
  context.callAsFunction()
 }

 @discardableResult
 func callResult<A>(
  _ body: @escaping () throws -> A
 ) rethrows -> A {
  precondition(
   context != .shared,
   "cannot called shared context, states must be initialized before handling"
  )
  defer { self.context.callAsFunction() }
  return try body()
 }

 func callAsFunction(_ newValue: @escaping @autoclosure () -> Value = ()) {
  precondition(
   context != .shared,
   "cannot called shared context, states must be initialized before handling"
  )
  wrappedValue = newValue()
  context.callAsFunction()
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
   self.callAsFunction()
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
  callAsFunction()
  context.objectWillChange.send()
 }

 func updateState() {
  context.objectWillChange.send()
 }
}
#endif

public extension ContextProperty {
 @inlinable
 @discardableResult
 func withUpdate<A>(
  _ body: @escaping () throws -> A
 ) async rethrows -> A {
  try body()
 }

 @inlinable
 func update(
  _ newValue: @escaping @autoclosure () -> Value = ()
 ) async {
  wrappedValue = newValue()
 }
}

public extension Module {
 typealias Context<Value> = ContextProperty<Value>
}

extension ContextProperty: CustomStringConvertible {
 public var description: String { String(describing: wrappedValue) }
}
