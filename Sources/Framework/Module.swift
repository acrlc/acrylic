public protocol Module: Identifiable {
 associatedtype VoidFunction: Module
 @Modular
 var void: VoidFunction { get }
}

public extension Module {
 @_disfavoredOverload
 @inlinable
 @discardableResult
 func callAsFunction() async throws -> Sendable {
  var detached = [Task<Sendable, Error>]()

  if let function = self as? any AsyncFunction {
   if function.detached {
    detached.append(
     Task.detached(priority: function.priority) {
      try await function.callAsyncFunction()
     }
    )
   } else {
    return try await function.callAsyncFunction()
   }
  } else if let function = self as? any Function {
   if function.detached {
    detached.append(
     Task.detached(priority: function.priority) {
      try await function.callAsFunction()
     }
    )
   } else {
    return try await function.callAsFunction()
   }
  } else {
   if avoid {
    return try await (self as? Modules)?.callAsFunction()
   } else {
    return try await void.callAsFunction()
   }
  }

  for task in detached {
   try await task.wait()
  }
  return ()
 }

 @_spi(ModuleReflection)
 @_disfavoredOverload
 @inlinable
 mutating func mutatingCallWithContext(id: AnyHashable? = nil) async throws {
  let id = id ?? AnyHashable(id)
  let shouldUpdate = await Reflection.states[id] != nil

  if !shouldUpdate {
   await Reflection.cacheIfNeeded(self, id: id)
  }

  let index = await Reflection.states[id].unsafelyUnwrapped.indices[0]
  let context = ModuleContext.cache[index.key]
   .unsafelyUnwrapped

  if shouldUpdate {
   await context.update()
  }

  try await context.callTasks()
  self = index.element as! Self
 }

 @_spi(ModuleReflection)
 @_disfavoredOverload
 @inlinable
 func callWithContext(id: AnyHashable? = nil) async throws {
  let id = id ?? AnyHashable(id)
  let shouldUpdate = await Reflection.states[id] != nil

  if !shouldUpdate {
   await Reflection.cacheIfNeeded(self, id: id)
  }

  let index = await Reflection.states[id].unsafelyUnwrapped.indices[0]
  let context = ModuleContext.cache[index.key]
   .unsafelyUnwrapped

  if shouldUpdate {
   await context.update()
  }

  try await context.callTasks()
 }

 @usableFromInline
 internal static var _mangledName: String {
  Swift._mangledTypeName(Self.self) ?? String(describing: Self.self)
 }

 @usableFromInline
 internal var _mangledName: String {
  Swift._mangledTypeName(Self.self) ?? String(describing: Self.self)
 }

 @usableFromInline
 internal var _typeName: String {
  Swift._typeName(Self.self)
 }

 @usableFromInline
 internal var _objectID: ObjectIdentifier {
  ObjectIdentifier(Self.self)
 }

 @_spi(ModuleReflection)
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
 public static let empty = Self()
 public var isEmpty: Bool { true }
 public init() {}
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
  }
 }
}

extension Module {
 @inlinable
 var avoid: Bool {
  VoidFunction.self is EmptyModule.Type ||
   VoidFunction.self is Never.Type
 }

 @inlinable
 public var hasVoid: Bool { !avoid }
}

import struct Core.EmptyID
public extension Module where ID == EmptyID {
 @_disfavoredOverload
 var id: EmptyID { EmptyID(placeholder: "\(Self.self)") }
}
