@_spi(ModuleReflection) import Acrylic
import struct Time.Timer

@_spi(ModuleTests)
public final class TestState<A: Testable>: StateActor, @unchecked Sendable {
 public static var unknown: Self { Self() }
 public let context = ModuleContext()
 public var baseTest: A { context.index.element as! A }
 var timer = Timer()

 public required init() {}

 @Reflection
 @discardableResult
 public func update() async throws -> (any Module)? {
  try await context.index.step(recurse)
 }

 @Reflection
 @usableFromInline
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

  if module.hasVoid || module is (any Testable) {
   if
    let test =
    try await (module as? any Testable)?.tests {
    let tests = (test as? Modules ?? [test])
    try await index.rebase(tests, recurse)
   } else {
    let void = try await module.void
    let voids = (void as? Modules ?? [void])
    try await index.rebase(voids, recurse)
   }
  }

  return module.finalizeTest(with: index, context: context, key: key)
 }
}

@_spi(ModuleReflection)
extension Tasks {
 @usableFromInline
 @discardableResult
 func callAsTest(
  index: ModuleIndex,
  context: ModuleContext,
  with state: isolated TestState<some Testable>
 ) async throws -> [Int: Sendable]? {
  let module = index.element

  let isTest = module is any TestProtocol
  lazy var test = (module as! any TestProtocol)

  defer {
   if isTest {
    index.element = test
   }
   else {
    index.element = module
   }
  }

  let name = module.typeConstructorName
  let baseName = index.start.element.typeConstructorName

  let label: String? = if isTest, let name = test.testName {
   name
  } else {
   module.idString
  }

  if !index.isStart {
   if isTest {
    try await test.setUp()
    if !test.silent {
     if let label {
      print(
       "\n[ \(label, style: .bold) ]",
       "\("starting", color: .cyan)",
       "\((module is any Tests) ? "Tests" : name, color: .cyan, style: .bold)",
       "❖"
      )
     }
    }
   }
  }

  guard queue.filter({ !$1.detached }).notEmpty else {
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

  do {
   var results: [Int: Sendable] = .empty

   state.timer.fire()
   let (keys, tasks) = (queue.keys, queue.values)
   for index in keys.indices {
    let (key, task) = (keys[index], tasks[index])

    if task.detached {
     detached.append((key, Task { try await task.perform() }))
    }
    else {
     results[key] = try await task.perform()
    }
   }

   endTime = timer.elapsed.description

   try await waitForDetached()

   let key = index.key
   var result = results[key].unsafelyUnwrapped
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
     module.idString == nil
      ? .empty
      : String.arrow.applying(color: .cyan, style: .boldDim) + .space +
      "\(module.idString!, color: .cyan, style: .bold)"
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
    try await test.onCompletion()
    try await test.cleanUp()
   }

   return results
  } catch {
   endTime = timer.elapsed.description

   let baseTest = state.baseTest
   let message = baseTest.errorMessage(
    with: label ?? name, for: error, at: isTest ? test.sourceLocation : nil
   )

   print(String.newline + message)
   print(endMessage + .newline)

   if isTest {
    try await test.cleanUp()
   }

   if
    (isTest && test.testMode == .break) || baseTest.testMode == .break {
    throw TestsError(message: message, sourceLocation: test.sourceLocation)
   }
  }
  return nil
 }
}

@_spi(ModuleTests)
@Reflection
extension ModuleContext {
 @usableFromInline
 func callTests(with state: TestState<some Testable>) async throws {
  defer { self.state = .idle }
  self.state = .active

  if tasks.queue.notEmpty {
   try await callTestResults(index: index, with: state)
  }

  if indices.count > 1 {
   for index in indices[1...] {
    let key = index.key
    if let context = cache[key] {
     try await context.callTestResults(index: index, with: state)
    }
   }
  }
 }

 @discardableResult
 func callTestResults(
  index: ModuleIndex,
  with state: TestState<some Testable>
 ) async throws -> [Int: Sendable]? {
  if let detachable = index.element as? Detachable, detachable.detached {
   try await tasks.callAsFunction()
  }

  return try await tasks.callAsTest(index: index, context: self, with: state)
 }
}

@_spi(ModuleTests)
@Reflection
public extension Reflection {
 /// Enables repeated calls from a base module using an id to retain state
 @discardableResult
 static func cacheTestIfNeeded<A: Testable>(
  _ module: A, key: Int
 ) async throws -> (Bool, TestState<A>) {
  guard let state = states[key] as? TestState<A> else {
   states.store(TestState<A>(), for: key)
   unowned var state: TestState<A> {
    get { states[key] as! TestState<A> }
    set { states[key] = newValue }
   }

   state.bind([module])

   let index = state.context.index

   index.element.prepareContext(from: index, actor: state)
   try await state.update()

   return (false, state)
  }
  return (true, state)
 }
}

@Reflection
extension TestProtocol {
 func _finalizeTest(
  with index: ModuleIndex, context: ModuleContext, key: Int
 ) -> any Module {
  context.tasks[queue: key] = AsyncTask {
   var copy = self
   defer { index.checkedElement = copy }
   return try await copy.callAsTest()
  }
  return self
 }
}

@Reflection
extension Module {
 @discardableResult
 func finalizeTest(
  with index: ModuleIndex, context: ModuleContext, key: Int
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
