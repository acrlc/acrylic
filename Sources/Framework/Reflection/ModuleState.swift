import struct Core.UnsafeRecursiveNode
@_spi(Reflection) import func ReflectionMirror._forEachFieldWithKeyPath

@_spi(ModuleReflection)
public protocol StateActor: Sendable {
 nonisolated(unsafe) var context: ModuleContext { get }
 @Reflection
 @discardableResult
 func update() async throws -> (any Module)?
 static var unknown: Self { get }
}

@_spi(ModuleReflection)
public typealias ModuleIndex = UnsafeRecursiveNode<Modules>
@_spi(ModuleReflection)
public typealias ModulePointer = UnsafeMutablePointer<any Module>

extension ModuleIndex: @unchecked Sendable {}

// MARK: - Default Implementation
@_spi(ModuleReflection)
public actor ModuleState: @unchecked Sendable, StateActor {
 public static var unknown: Self { Self() }
 public nonisolated(unsafe) var context = ModuleContext()
 public init() {}
}

@_spi(ModuleReflection)
@Reflection
public extension StateActor {
 @_disfavoredOverload
 func update() async throws -> (any Module)? {
  await context.invalidate()
  context.invalidateSubrange()
  return try await context.index.step(recurse)
 }

 @discardableResult
 func recurse(_ index: ModuleIndex) async throws -> (any Module)? {
  var module: any Module {
   get { index.element }
   set { index.element = newValue }
  }

  assert(
   module.notEmpty,
   """
   `\(module)` is empty, modules within `\(#function)` cannot be empty, \
   especially when conforming to `ExpressibleAsEmpty`.
   """
  )

  let key = index.key
  let context = cached(index, key: key) ?? context

  if module.hasVoid {
   let void = try await module.void
   let voids = void as? Modules ?? [void]

   try await index.rebase(voids, recurse)
  }

  return module.finalize(with: index, context: context, key: key)
 }
}

@_spi(ModuleReflection)
@Reflection
public extension ModuleIndex {
 @discardableResult
 /// Start indexing from the current index
 func step(
  _ content: (Self) async throws -> Element?
 ) async rethrows -> Element? {
  try await content(self)
 }

 /// Add base values to the current index
 func rebase(
  _ elements: Base,
  _ content: (Self) async throws -> Element?
 ) async rethrows {
  for element in elements {
   let projectedIndex = indices.endIndex
   let projectedOffset = base.endIndex
   base.append(element)

   var projection: Self = .next(with: self)
   projection.index = projectedIndex
   projection.offset = projectedOffset

   if try await content(projection) != nil {
    indices.insert(projection, at: projectedIndex)
   } else if projectedOffset < base.endIndex {
    base.remove(at: projectedOffset)
   }
  }
 }
}

@_spi(ModuleReflection)
@Reflection
public extension StateActor {
 static func initialize(
  id: AnyHashable? = nil,
  with module: some Module
 ) async throws -> Self {
  let key = (id?.base as? Int) ?? id?.hashValue ?? module.__key

  guard let state = Reflection.states[key] as? Self else {
   let initialState: Self = .unknown
   var state: Self {
    get { Reflection.states[key].unsafelyUnwrapped as! Self }
    set { Reflection.states[key] = newValue }
   }

   state = initialState
   initialState.bind([module])

   let index = initialState.context.index

   index.element.prepareContext(from: index, actor: initialState)
   try await initialState.update()

   return initialState
  }
  return state
 }
}

@_spi(ModuleReflection)
public extension StateActor {
 func bind(_ base: Modules) {
  let basePointer = withUnsafeMutablePointer(to: &context.modules) { $0 }
  let indicesPointer = withUnsafeMutablePointer(to: &context.indices) { $0 }

  basePointer.pointee.append(contentsOf: base)
  indicesPointer.pointee.append(context.index)
  indicesPointer.pointee[0]._base = basePointer
  indicesPointer.pointee[0]._indices = indicesPointer

  context.index = context.indices[0]
 }
}

// MARK: - Helper Extensions
@_spi(ModuleReflection)
@Reflection
public extension StateActor {
 @discardableResult
 func cached(
  _ index: ModuleIndex, key: Int
 ) -> ModuleContext? {
  if index.isStart {
   assert(context.actor != nil, "an actor must exist on the current context")
   return nil
  } else if let context = context.cache[key] {
   return context
  } else {
   let newContext = index.element.newContext(from: index, actor: self)
   context.cache[key] = newContext
   index.element.assign(to: newContext)
   return newContext
  }
 }
}

@_spi(ModuleReflection)
@Reflection
public extension Function {
 func queue(
  on index: ModuleIndex,
  from context: ModuleContext, with key: Int
 ) -> Self {
  context.tasks[queue: key] = AsyncTask(
   priority: priority, detached: detached
  ) { @Sendable in
   try self.callAsFunction()
  }
  return self
 }
}

@_spi(ModuleReflection)
@Reflection
public extension AsyncFunction {
 func queueAsync(
  on index: ModuleIndex,
  from context: ModuleContext, with key: Int
 ) -> Self {
  context.tasks[queue: key] = AsyncTask(
   priority: priority, detached: detached
  ) {
   try await self.callAsFunction()
  }
  return self
 }
}

@_spi(ModuleReflection)
@Reflection
public extension Module {
 func finalize(
  with index: ModuleIndex, context: ModuleContext, key: Int
 ) -> any Module {
  if let task = self as? any AsyncFunction {
   task.queueAsync(on: index, from: context, with: key)
  } else if let task = self as? any Function {
   task.queue(on: index, from: context, with: key)
  } else {
   self
  }
 }

 func newContext(
  from index: ModuleIndex,
  actor: some StateActor
 ) -> ModuleContext {
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
   index: index, actor: actor,
   properties: properties.wrapped
  )
 }

 consuming func prepareContext(
  from index: consuming ModuleIndex,
  actor: some StateActor
 ) {
  let context = actor.context
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

  context.index = index
  context.actor = actor
  context.properties = properties.wrapped
 }
}

@_spi(ModuleReflection)
@Reflection
public extension ContextualProperty {
 func set<Root>(
  on value: inout Root,
  with context: ModuleContext,
  keyPath: AnyKeyPath
 ) {
  var copy = self
  if self.context == .unknown {
   copy.initialize(with: context)
  } else {
   copy.initialize()
  }
  let writableKeyPath = keyPath as! WritableKeyPath<Root, Self>
  value[keyPath: writableKeyPath] = copy
 }
}

@_spi(ModuleReflection)
@Reflection
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

// - MARK: Extensions
@_spi(ModuleReflection)
public extension ModuleIndex {
 var isStart: Bool {
  index == .zero && offset == .zero
 }

 @inline(__always)
 var key: Int { hashValue }
}

@_spi(ModuleReflection)
extension ModuleIndex: CustomStringConvertible {
 public var description: String {
  if element.isIdentifiable {
   let desc = String(describing: element.id).readableRemovingQuotes
   if desc != "nil" {
    return
     """
     \(element.typeConstructorName)\
     [\(desc)](\(index), \(offset)) | \(range ?? 0 ..< 0)
     """
   }
  }
  return
   """
   \(element.typeConstructorName)(\(index), \(offset) | \(range ?? 0 ..< 0))
   """
 }
}

@_spi(ModuleReflection)
public extension Module {
 static var typeConstructorName: String {
  let name = Swift._typeName(Self.self)
  let bracketCount = name.count(for: "<")

  func filtered(_ split: [Substring]) -> String {
   var string = split.dropFirst().joined(separator: ".")

   let prefixes = ["CombineModules", "Modular", "Modular.Functions"]
   for prefix in prefixes where string.hasPrefix(prefix) {
    string.removeSubrange(string.startIndex ... prefix.endIndex)
    break
   }

   return string
  }

  switch bracketCount {
  case 0:
   return filtered(name.split(separator: "."))
  case 1:
   return String(
    filtered(name.prefix(while: { $0 != "<" }).split(separator: "."))
   )
  default:

   var startIndex = name.startIndex
   var offset = startIndex
   var substrings: [Substring] = .empty

   while offset < name.endIndex {
    let character = name[offset]
    if character == "<" {
     if let bracketed = name[offset...].break(from: "<", to: ">") {
      let endIndex = bracketed.endIndex

      guard endIndex < name.endIndex else {
       let substring = name[name.startIndex ..< bracketed.startIndex]

       if substring.count(for: ".") > 0 {
        return filtered(substring.split(separator: "."))
       } else {
        return String(substring)
       }
      }

      substrings.append(name[startIndex ..< offset])
      startIndex = name.index(after: endIndex)
      offset = name.index(after: endIndex)
     } else {
      break
     }
    } else {
     offset = name.index(after: offset)
    }
   }

   return filtered(substrings)
  }
 }

 @_transparent
 var typeConstructorName: String { Self.typeConstructorName }

 var idString: String? {
  if isIdentifiable {
   let id: ID? = if let id = self.id as? (any ExpressibleByNilLiteral) {
    nil ~= id ? nil : self.id
   } else {
    id
   }

   guard let id else {
    return nil
   }

   let string = String(describing: id).readableRemovingQuotes
   if !string.isEmpty, string != "nil" {
    return string
   }
  }
  return nil
 }

 var debugDescription: String {
  if isIdentifiable {
   let desc = String(describing: id).readableRemovingQuotes
   if desc != "nil" {
    return "\(typeConstructorName) [\(desc)]"
   }
  }
  return typeConstructorName
 }
}

@_spi(ModuleReflection)
public extension Module {
 var isIdentifiable: Bool {
  !(ID.self is Never.Type) && !(ID.self is EmptyID.Type)
 }
}
