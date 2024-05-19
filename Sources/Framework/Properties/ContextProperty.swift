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
    $0[id].unsafelyUnwrapped as? Value ?? initialValue as! Value
   }
  }
  nonmutating set {
   context.values.withWriterLockVoid { $0[self.id] = newValue }
  }
 }

 public init() {}
 @inlinable
 public var projectedValue: Self { self }
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
 @inlinable
 init(wrappedValue: Value) { initialValue = wrappedValue }

 init() where Value: ExpressibleByNilLiteral {
  initialValue = Value(nilLiteral: ())
 }

 @_disfavoredOverload
 @inlinable
 init() where Value: Infallible { initialValue = Value.defaultValue }

 @inlinable
 static func constant(_ value: Value) -> Self {
  self.init(wrappedValue: value)
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
 @inlinable
 @discardableResult
 func withUpdate<A: Sendable>(
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
 public var description: String {
  String(describing: wrappedValue).readable
 }
}
