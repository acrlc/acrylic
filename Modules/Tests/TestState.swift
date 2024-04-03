@_spi(ModuleReflection) import Acrylic
import struct Time.Timer

@usableFromInline
final class TestState<A: Testable>: ModuleState {
 override public init() { super.init() }
 var timer = Timer()
 var baseTest: A { values[0] as! A }

 func recurse(_ index: Index) async throws -> Element? {
  var module: Element {
   get { index.element }
   set { index.element = newValue }
  }

  let key = index.key

  let context =
   ModuleContext.cache.withLockUnchecked { $0[key] } ??
   .cached(index, with: self, key: key)

  if module.hasVoid || module is (any Testable) {
   let void =
    try await (module as? any Testable)?.tests as? Modules ??
    module.void
   let voids = (void as? Modules ?? [void])

   try await index.rebase(voids, recurse)
  }

  return module.finalizeTest(with: index, context: context, key: key)
 }
}

extension ModuleState.Index {
 @discardableResult
 /// Start indexing from the current index
 func step(_ content: (Self) async throws -> Element?) async rethrows
  -> Element? {
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

extension ModuleState.Index {
 var isStart: Bool {
  index == .zero && offset == .zero
 }
}

extension Tasks {
 @_spi(ModuleReflection)
 @usableFromInline
 @discardableResult
 func callAsTest(
  from context: ModuleContext, with state: TestState<some Testable>
 ) async throws -> [Sendable]? {
  cancel()

  let current = operations
  removeAll()

  let index = context.index.withLockUnchecked { $0 }

  let test = index.element

  let isTest = test is any TestProtocol

  let name = test.typeConstructorName
  let baseName =
   context.index.withLockUnchecked { $0.start.element }.typeConstructorName
  let label: String? = if
   let test = test as? any Testable,
   let name = test.testName {
   name
  } else {
   test.idString
  }

  if !index.isStart {
   if isTest {
    try await (test as! any TestProtocol).setUp()
    if let label {
     print(
      "\n[ \(label, style: .bold) ]",
      "\("starting", color: .cyan)",
      "\(name, color: .cyan, style: .bold)",
      "❖"
     )
    } else {
     print(
      "\n[ \(name, color: .cyan, style: .bold) ]", "\("starting", style: .dim)",
      "❖"
     )
    }
   }
  }

  guard current.filter({ !$0.detached }).notEmpty else {
   return nil
  }

  var timer: Timer {
   get { state.timer }
   set { state.timer = newValue }
  }

  var endTime: String
  var endMessage: String {
   "\("after", color: .cyan, style: .bold)" + .space +
    "\(endTime + .space, style: .boldDim)"
  }

  task = Task {
   var results: [Sendable] = .empty

   state.timer.fire()

   for task in current {
    if task.detached {
     self.detached.append(Task { try await task() })
    }
    else {
     try await results.append(task())
    }
   }
   return results
  }

  do {
   let results = try await task.unsafelyUnwrapped.value

   endTime = timer.elapsed.description

   for task in detached {
    try await task.wait()
   }

   var result = results[0]
   var valid = true

   print(
    String.space,
    "\(isTest ? "passed" : "called", color: .cyan, style: .bold)",
    "\(name, color: .cyan)", terminator: .space
   )

   if isTest {
    print(
     String.bullet + .space +
      "\(label == name ? .empty : baseName, style: .boldDim)"
    )
   } else {
    print(
     test.idString == nil
      ? .empty
      : String.arrow.applying(color: .cyan, style: .boldDim) + .space +
      "\(test.idString!, color: .cyan, style: .bold)"
    )
   }

   if let results = result as? [Sendable] {
    result = results._validResults
    valid = results.filter { ($0 as? [Sendable])?.notEmpty ?? false }.isEmpty
   } else if !result._isValid {
    valid = false
   }

   if valid {
    print(
     String.space,
     "\("return", style: .boldDim)",
     "\("\(result)".readableRemovingQuotes, style: .bold) ",
     terminator: .empty
    )
   } else {
    print(String.space, terminator: .space)
   }

   print(endMessage)

   if isTest {
    try await (test as! any TestProtocol).onCompletion()
    try await (test as! any TestProtocol).cleanUp()
   }

   return results
  } catch {
   endTime = timer.elapsed.description

   let message = state.baseTest.errorMessage(with: label ?? name, for: error)

   print(String.newline + message)
   print(endMessage + .newline)

   if
    (test as? any TestProtocol)?.testMode ?? state.baseTest.testMode == .break {
    if isTest {
     try await (test as! any TestProtocol).cleanUp()
    }

    throw TestsError(message: message)
   }
  }
  return nil
 }
}

extension ModuleContext {
 func callTests(with state: TestState<some Testable>) async throws {
  try await index.withLockUnchecked { baseIndex in
   let baseIndex = baseIndex
   let task = Task {
    let baseModule = baseIndex.element
    self.results = .empty
    self.results![baseIndex.key] =
     try await self.callTestResults(baseModule, with: state)

    let baseIndices = baseIndex.indices
    guard baseIndices.count > 1 else {
     return
    }

    let indices = baseIndices.dropFirst().map {
     ($0, $0.context.unsafelyUnwrapped)
    }

    for (index, context) in indices {
     self.results![index.key] =
      try await context.callTestResults(index.element, with: state)
    }
   }

   self.calledTask = task
   return task
  }.value
 }

 @discardableResult
 func callTestResults(
  _ value: any Module, with state: TestState<some Testable>
 ) async throws -> [Sendable]? {
  if let detachable = value as? Detachable, detachable.detached {
   return try await tasks.callAsFunction()
  }

  return try await tasks.callAsTest(from: self, with: state)
 }
}

extension Reflection {
 /// Enables repeated calls from a base module using an id to retain state
 @usableFromInline
 @discardableResult
 static func cacheTestIfNeeded<A: Testable>(
  _ module: A,
  id: AnyHashable
 ) async throws -> Bool {
  if states[id] == nil {
   let initialState = TestState<A>()
   unowned var state: TestState<A> {
    get { states[id].unsafelyUnwrapped as! TestState<A> }
    set {
     states[id] = newValue
    }
   }

   state = initialState

   let values =
    withUnsafeMutablePointer(to: &state.values) { $0 }
   let indices =
    withUnsafeMutablePointer(to: &state.indices) { $0 }

   ModuleState.Index.bind(
    base: [module],
    basePointer: values,
    indicesPointer: indices
   )

   let index = initialState.indices[0]

   try await index.step(initialState.recurse)

   return false
  }
  return true
 }
}

extension TestProtocol {
 func _finalizeTest(
  with index: ModuleState.Index, context: ModuleContext, key: AnyHashable
 ) -> any Module {
  context.tasks.queue[key] = AsyncTask<Output, Never>(
   id: key,
   context: context
  ) {
   try await self.callAsTest()
  }
  return self
 }
}

public extension Module {
 @discardableResult
 func finalizeTest(
  with index: ModuleState.Index, context: ModuleContext, key: AnyHashable
 ) -> any Module {
  if
   self is (any Function) || self is (any AsyncFunction) ||
   self is (any Testable) {
   return finalize(with: index, context: context, key: key)
  } else if let test = self as? (any TestProtocol) {
   return test._finalizeTest(with: index, context: context, key: key)
  }
  return self
 }
}

/* MARK: - Test Helpers */
public extension Task {
 @discardableResult
 func wait() async throws -> Success {
  try await value
 }
}

public extension Task where Failure == Never {
 @discardableResult
 func wait() async -> Success {
  await value
 }
}

extension Module {
 @usableFromInline
 var isIdentifiable: Bool {
  !(ID.self is Never.Type) && !(id is EmptyID)
 }
}

extension ModuleState.Index: CustomStringConvertible {
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
  return "\(element.typeConstructorName)(\(index), \(offset) | \(range ?? 0 ..< 0))"
 }
}
