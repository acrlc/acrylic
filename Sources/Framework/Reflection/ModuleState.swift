import struct Core.UnsafeRecursiveNode
import struct os.OSAllocatedUnfairLock
@_spi(Reflection) import func ReflectionMirror._forEachFieldWithKeyPath

@usableFromInline typealias AnyModule = any Module
@usableFromInline
typealias ModuleIndex = UnsafeRecursiveNode<Modules>

open class ModuleState {
 public typealias Base = Modules
 public typealias Index = UnsafeRecursiveNode<Modules>
 public typealias Value = Index.Value
 public typealias Values = Index.Values
 public typealias Indices = Index.Indices
 static let unknown = ModuleState()
 @_spi(ModuleReflection)
 public var values: Values = .empty
 @_spi(ModuleReflection)
 public var indices: Indices = .empty
 @_spi(ModuleReflection)
 public init() {}
}

@_spi(ModuleReflection)
public extension ModuleState {
 @inlinable
 func callAsFunction(_ context: ModuleContext) async throws {
  try await context.phase.withLockUnchecked {
   context.cancel()
   _ = context.index.withLockUnchecked { $0.step(recurse) }
   return Task { try await context.callTasks() }
  }.value
 }

 @inlinable
 func update(_ context: ModuleContext) {
  context.phase.withLockUnchecked {
   context.cancel()
   _ = context.index.withLockUnchecked { $0.step(recurse) }
  }
 }

 @inlinable
 @discardableResult
 internal func recurse(_ index: Index) -> Value? {
  var module: Value {
   get { index.value }
   set { index.value = newValue }
  }

  let key = index.key

  let context =
   ModuleContext.cache.withLockUnchecked { $0[key] } ??
   .cached(index, with: self, key: key)

  if module.hasVoid {
   let void = module.void
   let voids = void as? Modules ?? [void]

   index.rebase(voids, recurse)
  }

  return module.finalize(with: index, context: context, key: key)
 }
}

// - MARK: Module Extensions
extension Module {
 @usableFromInline
 var isIdentifiable: Bool {
  !(ID.self is Never.Type) && !(id is EmptyID)
 }

 @usableFromInline
 func context(from index: ModuleIndex, state: ModuleState) -> ModuleContext {
  var properties = DynamicProperties()

  _forEachFieldWithKeyPath(
   of: Self.self,
   options: .ignoreUnknown
  ) { char, keyPath in
   let label = String(cString: char)
   if
    label.hasPrefix("_"),
    let property = self[keyPath: keyPath] as? any ContextualProperty {
    properties.append((label, keyPath, property))
   }
   return true
  }

  return ModuleContext(
   index: index, state: state,
   properties: properties.wrapped
  )
 }
}

extension ContextualProperty {
 func set<Root>(
  on value: inout Root,
  with context: ModuleContext,
  keyPath: AnyKeyPath
 ) {
  var copy = self
  if self.context == .shared {
   copy.initialize(with: context)
  } else {
   copy.initialize()
  }
  let writableKeyPath = keyPath as! WritableKeyPath<Root, Self>
  value[keyPath: writableKeyPath] = copy
 }
}

public extension Module {
 mutating func assign(to context: ModuleContext) {
  if let properties = context.properties {
   for (_, keyPath, property) in properties {
    let property = property as! any ContextualProperty
    property.set(on: &self, with: context, keyPath: keyPath)
   }
  }
 }
}

@_spi(ModuleReflection)
extension Function {
 @inlinable
 func queue(
  on index: ModuleIndex,
  from context: ModuleContext, with key: AnyHashable
 ) -> Self {
  context.tasks.queue[key] =
   AsyncTask<Output, Never>(
    id: key,
    priority: priority,
    detached: detached,
    context: context
   ) {
    try await self.callAsFunction()
   }
  return self
 }
}

@_spi(ModuleReflection)
extension AsyncFunction {
 @inlinable
 func queueAsync(
  on index: ModuleIndex,
  from context: ModuleContext, with key: AnyHashable
 ) -> Self {
  context.tasks.queue[key] =
   AsyncTask<Output, Never>(
    id: key,
    priority: priority,
    detached: detached,
    context: context
   ) {
    try await self.callAsyncFunction()
   }
  return self
 }
}

public extension Module {
 @_spi(ModuleReflection)
 func finalize(
  with index: ModuleState.Index, context: ModuleContext, key: AnyHashable
 ) -> any Module {
  if let task = self as? any AsyncFunction {
   task.queueAsync(on: index, from: context, with: key)
  } else if let task = self as? any Function {
   task.queue(on: index, from: context, with: key)
  } else {
   self
  }
 }
}

// MARK: - Extensions
extension Hashable {
 var readable: String {
  String(describing: self).readable
 }
}

@_spi(ModuleReflection)
public extension ModuleContext {
 @discardableResult
 static func cached(
  _ index: ModuleState.Index, with state: ModuleState, key: AnyHashable
 ) -> ModuleContext {
  ModuleContext.cache.withLockUnchecked {
   $0[key] = index.value.context(from: index, state: state)
   let context = $0[key].unsafelyUnwrapped
   index.value.assign(to: context)
   return context
  }
 }
}

@_spi(ModuleReflection)
public extension ModuleState {
 static func initialize<A: Module>(with module: A) -> ModuleState {
  var state: ModuleState {
   get { Reflection.states[A._mangledName].unsafelyUnwrapped }
   set { Reflection.states[A._mangledName] = newValue }
  }

  state = ModuleState()

  let values = withUnsafeMutablePointer(to: &state.values) { $0 }
  let indices = withUnsafeMutablePointer(to: &state.indices) { $0 }

  ModuleIndex.bind(
   base: [module], values: &values.pointee,
   indices: &indices.pointee
  )

  indices.pointee[0][0].step(state.recurse)

  return state
 }
}

public extension ModuleState.Index {
 var typeName: String { value._typeName }
 var mangledName: String { value._mangledName }
 var objectID: ObjectIdentifier { value._objectID }
 var id: String {
  if value.isIdentifiable {
   let description = String(describing: value.id).readableRemovingQuotes
   if description != "nil" {
    return "\(mangledName)[\(description)](\(hashValue))"
   }
  }
  return "\(mangledName)(\(hashValue))"
 }

 var key: Int { id.hashValue }

 var context: ModuleContext? {
  ModuleContext.cache.withLockUnchecked { $0[self.key] }
 }
}
