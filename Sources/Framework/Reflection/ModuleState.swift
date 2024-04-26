import struct Core.UnsafeRecursiveNode
@_spi(Reflection) import func ReflectionMirror._forEachFieldWithKeyPath

@usableFromInline typealias AnyModule = any Module
@usableFromInline
typealias ModuleIndex = UnsafeRecursiveNode<Modules>
extension ModuleState.Index: @unchecked Sendable {}

open class ModuleState: @unchecked Sendable {
 public typealias Base = Modules
 public typealias Index = UnsafeRecursiveNode<Modules>
 public typealias Element = Index.Element
 public typealias Values = Index.Base
 public typealias Indices = Index.Indices
 static let unknown = ModuleState()
 @_spi(ModuleReflection)
 public var mainContext: ModuleContext = .shared
 @_spi(ModuleReflection)
 public var values: Values = .empty
 @_spi(ModuleReflection)
 public var indices: Indices = .empty
 @_spi(ModuleReflection)
 public init() {}
}

extension ModuleState {
 @usableFromInline
 @discardableResult
 func recurse(_ index: Index) -> Element? {
  var module: Element {
   get { index.element }
   set { index.element = newValue }
  }

  let key = index.key

  let context =
   mainContext.cache[key] ?? .cached(index, with: self, key: key)

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
  !(ID.self is Never.Type) && !(ID.self is EmptyID.Type)
 }

 @usableFromInline
 func context(from index: ModuleIndex, state: ModuleState) -> ModuleContext {
  var properties = DynamicProperties()

  _forEachFieldWithKeyPath(of: Self.self) { char, keyPath in
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
  guard state.mainContext != .shared else {
   let context = index.element.context(from: index, state: state)
   state.mainContext = context
   return context
  }
  let context = index.element.context(from: index, state: state)
  state.mainContext.cache[key] = context
  index.element.assign(to: context)
  return context
 }
}

@_spi(ModuleReflection)
@Reflection(unsafe)
public extension ModuleState {
 static func initialize<A: Module>(with module: A) -> ModuleState {
  let initialState = ModuleState()

  var state: ModuleState {
   get { Reflection.states[A._mangledName].unsafelyUnwrapped }
   set { Reflection.states[A._mangledName] = newValue }
  }

  state = initialState

  let values = withUnsafeMutablePointer(to: &state.values) { $0 }
  let indices = withUnsafeMutablePointer(to: &state.indices) { $0 }

  ModuleIndex.bind(
   base: [module],
   basePointer: &values.pointee,
   indicesPointer: &indices.pointee
  )

  let index = indices.pointee[0]

  initialState.mainContext = .cached(index, with: initialState, key: index.key)

  index.step(state.recurse)

  return state
 }
}

public extension ModuleState.Index {
 var typeName: String { element._typeName }
 var mangledName: String { element._mangledName }
 var objectID: ObjectIdentifier { element._objectID }
 var id: String {
  if element.isIdentifiable {
   let desc = String(describing: element.id).readableRemovingQuotes
   if desc != "nil" {
    return "\(mangledName)[\(desc)](\(hashValue))"
   }
  }
  return "\(mangledName)(\(hashValue))"
 }

 var key: Int { id.hashValue }
}
