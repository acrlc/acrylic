@_spi(ModuleReflection) import Acrylic
import struct Time.Timer

@usableFromInline
final class TestState<A: Testable>: ModuleState {
 override public init() { super.init() }
 var timer = Timer()
 var baseTest: A { values[0][0] as! A }

 func rebase(
  _ index: Index, with voids: Modules,
  _ content: (Index) async throws -> Value?
 ) async rethrows {
  if voids.notEmpty {
   if let voids = voids as? [[Value]] {
    if voids.count == 1 {
     // rebase void array
     try await index.rebase(voids.first!, content)
    } else {
     // rebase recursive array
     try await index.rebase(voids, content)
    }
   } else {
    // rebase array array
    try await index.rebase(voids, content)
   }
  }
 }

 func recurse(_ index: Index) async throws -> Value? {
  var module: Value {
   get { index.value }
   set { index.value = newValue }
  }

  if index != .start, let voids = module as? Modules {
   // rebase using the start index
   try await rebase(start, with: voids, recurse)
  } else {
   let key = module._id(from: index)
   let context =
    ModuleContext.cache.withLockUnchecked { $0[key] } ??
    .cached(index, with: self, key: key)

   if module.hasVoid || module is (any Testable) {
    defer { self.start = nil }
    start = index
    // recurse if module contains void
    if let tests = try await (module as? any Testable)?.tests as? Modules {
     if !index.isStart {
      assert(!(index.value is A), "A test cannot recursively contain itself")
     }
     try await index.rebase(tests, recurse)
    } else if module.void.notEmpty {
     try await index.rebase(module.void as? Modules ?? [module.void], recurse)
    }
   }
   return module.finalizeTest(with: index, context: context, key: key)
  }
  return nil
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

  let test = index.value

  let isTest = test is any TestProtocol

  if isTest {
   try await (test as! any TestProtocol).setUp()
  }

  let name = test.typeConstructorName
  let baseName =
   context.index.withLockUnchecked { $0.start.value }.typeConstructorName
  let label: String? = if
   let test = test as? any Testable,
   let name = test.testName {
   name
  } else {
   test.idString
  }

  if !index.isStart {
   if isTest {
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

  timer.fire()
  task = Task {
   var results: [Sendable] = .empty
   for task in current {
    if task.detached {
     Task { try await task() }
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
    let baseModule = baseIndex.value
    self.results = .empty
    self.results![baseModule._id(from: baseIndex)] =
     try await self.callTestResults(baseModule, with: state)

    let baseElements = baseIndex.elements
    guard baseElements.count > 1 else {
     return
    }
    let elements = baseElements.dropFirst()
    for index in elements {
     let module = index.value
     let context = module._context(from: index).unsafelyUnwrapped

     self.results![module._id(from: index)] =
      try await context.callTestResults(module, with: state)
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

   ModuleState.Index.bind(base: [module], values: values, indices: indices)

   let index = initialState.indices[0][0]

   try await index.step(initialState.recurse)
   initialState.start = nil

   return false
  }
  return true
 }
}

extension ModuleState.Index {
 @discardableResult
 /// Start indexing from the current index
 func step(_ content: (Self) async throws -> Value?) async rethrows -> Value? {
  try await content(self)
 }

 /// Add base values to the current index
 func rebase(
  _ base: Base,
  _ content: (Self) async throws -> Value?
 ) async rethrows {
  for element in base {
   let projectedIndex = elements.endIndex
   let projectedOffset = self.base.endIndex
   let projection: Self = .next(with: self)
   self.base.append(element)

   if try await content(projection) != nil {
    elements.insert(projection, at: projectedIndex)
   } else {
    self.base.remove(at: projectedOffset)
   }
  }
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
