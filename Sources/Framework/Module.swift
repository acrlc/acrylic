public protocol Module: Identifiable {
 associatedtype VoidFunction: Module
 @Modular
 var void: VoidFunction { get async throws }
}

public extension Module {
 @_disfavoredOverload
 func callAsVoid() async throws {
  var detached = [Task<Sendable, Error>]()

  if let function = self as? any AsyncFunction {
   if function.detached {
    detached.append(
     Task.detached(priority: function.priority) {
      try await function.callAsFunction()
     }
    )
   } else {
    try await function.callAsFunction()
   }
  } else if let function = self as? any Function {
   if function.detached {
    detached.append(
     Task.detached(priority: function.priority) {
      try function.callAsFunction()
     }
    )
   } else {
    try function.callAsFunction()
   }
  } else {
   if avoid {
    try await (self as? Modules)?.callAsFunction()
   } else {
    try await void.callAsVoid()
   }
  }

  for task in detached {
   try await task.wait()
  }
  return ()
 }

 @_spi(ModuleReflection)
 var __key: Int {
  !(ID.self is Never.Type) && !(ID.self is EmptyID.Type) &&
   String(describing: id).readableRemovingQuotes != "nil" ?
   id.hashValue : (
    Swift._mangledTypeName(Self.self) ?? String(describing: Self.self)
   ).hashValue
 }

 @_spi(ModuleReflection)
 @_disfavoredOverload
 @Reflection
 @inlinable
 mutating func mutatingCallWithContext(id: AnyHashable? = nil) async throws {
  let key = id?.hashValue ?? __key
  let shouldUpdate = Reflection.states[key] != nil

  if !shouldUpdate {
   try await Reflection.asyncCacheIfNeeded(
    id: key,
    module: self,
    stateType: ModuleState.self
   )
  }

  let state = Reflection.states[key].unsafelyUnwrapped
  let index = state.context.index
  let context = state.context

  if shouldUpdate {
   try await context.update()
  }

  try await context.callTasks()
  self = index.element as! Self
 }

 @_spi(ModuleReflection)
 @_disfavoredOverload
 @inlinable
 func callWithContext(id: AnyHashable? = nil) async throws {
  let key = id?.hashValue ?? __key
  let shouldUpdate = await Reflection.states[key] != nil

  if !shouldUpdate {
   try await Reflection.cacheIfNeeded(
    id: key,
    module: self,
    stateType: ModuleState.self
   )
  }

  let state = await Reflection.states[key].unsafelyUnwrapped
  let context = state.context

  if shouldUpdate {
   try await context.update()
  }

  try await context.callTasks()
 }

 @usableFromInline
 internal static var _mangledName: String {
  Swift._mangledTypeName(Self.self) ?? String(describing: Self.self)
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
  switch self {
  case let `self` as [[any Module]]: self.allSatisfy(\.isEmpty)
  case let `self` as [any Module]: self.allSatisfy(\.isEmpty)
  case let `self` as any ExpressibleAsEmpty: self.isEmpty
  case is EmptyModule: true
  default: false
  }
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

public extension Module {
 @inlinable
 var avoid: Bool {
  VoidFunction.self is EmptyModule.Type ||
   VoidFunction.self is Never.Type
 }

 @inlinable
 var hasVoid: Bool { !avoid }
}

import struct Core.EmptyID
public extension Module where ID == EmptyID {
 @_disfavoredOverload
 var id: EmptyID { EmptyID(placeholder: "\(Self.self)") }
}
