public protocol Module: Identifiable {
 associatedtype VoidFunction: Module
 /// The contextual building blocks for modules that allows the
 /// creation of a repeatable structure and shared context either through
 /// Some applications require static functionality which doesn't update the
 /// structure of a module
 /// Some applications require dynamic functionality which updates the structure
 /// of a module and it's tasks
 /// Some application require
 @Modular
 var void: VoidFunction { get }
}

extension Module {
 @_disfavoredOverload
 @inlinable
 @discardableResult
 public func callAsFunction() async throws -> Sendable {
  if let function = self as? any AsyncFunction {
   try await function.callAsyncFunction()
  } else if let function = self as? any Function {
   try await function.callAsFunction()
  } else {
   if avoid {
    try await (self as? Modules)?.callAsFunction()
   } else {
    try await void.callAsFunction()
   }
  }
 }

 @_spi(ModuleReflection)
 @_disfavoredOverload
 @inlinable
 public mutating func mutatingCallWithContext(id: AnyHashable? = nil) async throws {
  let id = id ?? AnyHashable(id)
  let shouldUpdate = Reflection.cacheIfNeeded(self, id: id)
  let index = Reflection.states[id].unsafelyUnwrapped.indices[0][0]
  let context = index.value._context(from: index).unsafelyUnwrapped

  if shouldUpdate {
   context.update()
   try await context.updateTask?.value
  }

  try await context.callTasks()
  self = index.value as! Self
 }
 
 @_spi(ModuleReflection)
 @_disfavoredOverload
 @inlinable
 public func callWithContext(id: AnyHashable? = nil) async throws {
  let id = id ?? AnyHashable(id)
  let shouldUpdate = Reflection.cacheIfNeeded(self, id: id)
  let index = Reflection.states[id].unsafelyUnwrapped.indices[0][0]
  let context = index.value._context(from: index).unsafelyUnwrapped
  
  if shouldUpdate {
   context.update()
   try await context.updateTask?.value
  }
  
  try await context.callTasks()
 }


 @usableFromInline
 static var _mangledName: String {
  Swift._mangledTypeName(Self.self) ?? String(describing: Self.self)
 }

 @usableFromInline
 static var _typeName: String {
  Swift._typeName(Self.self)
 }

 @usableFromInline
 var _type: ModuleType {
  self is any AsyncFunction
   ? .asyncFunction
   : self is any Function ? .function : .module
 }
}

// Note: Allows declaring `exit` or `fatalError` within modules
extension Never: Module {
 public var void: some Module { Modules.empty }
}

public extension Module where VoidFunction == Never {
 var void: Never { fatalError("body for \(Self.self) cannot be Never") }
}

// MARK: - Default Modules
public struct EmptyModule: Module, ExpressibleAsEmpty {
 public typealias Body = Never
 public static var empty = Self()
 public var isEmpty: Bool { true }
 public init() {}
}

public extension Module {
 typealias Empty = EmptyModule
 @_transparent
 var empty: Empty { .empty }
}

@_spi(ModuleReflection)
public extension Module {
 @_disfavoredOverload
 var isEmpty: Bool {
  (self as? any ExpressibleAsEmpty)?.isEmpty ??
   (self as? Modules)?.isEmpty ?? false
 }

 @_disfavoredOverload
 var notEmpty: Bool { !isEmpty }
}

// MARK: - Protocol add-ons
extension Optional: Identifiable where Wrapped: Module {
 public var id: Wrapped.ID? { self?.id }
}

extension Optional: Module where Wrapped: Module {
 @Modular
 public var void: some Module {
  if let self {
   self
  } else {
   empty
  }
 }
}

extension Module {
 @inlinable
 var avoid: Bool { VoidFunction.self is Never.Type }
 @inlinable
 public var hasVoid: Bool { !avoid }
}

import struct Core.EmptyID
public extension Module where ID == EmptyID {
 @_disfavoredOverload
 var id: EmptyID { EmptyID(placeholder: "\(Self.self)") }
}
