public protocol ContextModule: Module {
 init()
}

@_spi(ModuleReflection)
@Reflection
public extension ContextModule {
 static var state: ModuleState {
  Reflection.cacheIfNeeded(
   id: _mangledName, module: { Self() }, stateType: ModuleState.self
  )
 }

 unowned static var context: ModuleContext { state.context }

 static func callContext() async throws {
  try await context.callAsFunction()
 }

 static func callContext(with state: ModuleContext.State) async throws {
  try await context.callAsFunction(with: state)
 }

 static func cancelContext() async {
  await context.cancel()
 }

 static func cancelContext(with state: ModuleContext.State) async {
  await context.cancel(with: state)
 }

 static func updateContext() async throws {
  try await context.update()
 }

 static func updateContext(with state: ModuleContext.State) async throws {
  try await context.update(with: state)
 }

 static func waitForContext() async throws {
  try await context.wait()
 }

 static func waitForAllOnContext() async throws {
  try await context.waitForAll()
 }
}

@Reflection(unsafe)
public extension ContextModule {
 func callContext() async throws {
  try await Self.callContext()
 }

 func callContext(with state: ModuleContext.State) async throws {
  try await Self.callContext(with: state)
 }

 func cancelContext() async {
  await Self.cancelContext()
 }

 func cancelContext(with state: ModuleContext.State) async {
  await Self.cancelContext(with: state)
 }

 func updateContext() async throws {
  try await Self.updateContext()
 }

 func updateContext(with state: ModuleContext.State) async throws {
  try await Self.updateContext()
 }

 func waitForContext() async throws {
  try await Self.waitForContext()
 }

 func waitForAllOnContext() async throws {
  try await Self.waitForAllOnContext()
 }

 nonisolated func callContext() {
  Task {
   try await Self.callContext()
  }
 }

 nonisolated func callContext(with state: ModuleContext.State) {
  Task {
   try await Self.callContext(with: state)
  }
 }

 nonisolated func cancelContext() {
  Task {
   await Self.cancelContext()
  }
 }

 nonisolated func cancelContext(with state: ModuleContext.State) {
  Task {
   await Self.cancelContext(with: state)
  }
 }

 nonisolated func updateContext() {
  Task {
   try await Self.updateContext()
  }
 }

 nonisolated func updateContext(with state: ModuleContext.State) {
  Task {
   try await Self.updateContext(with: state)
  }
 }

 nonisolated func withContext(
  action: @Reflection @escaping (ModuleContext) async throws -> ()
 ) {
  Task { @Sendable in
   try await action(Self.context)
  }
 }

 nonisolated func withContext(
  action: @Reflection @escaping (ModuleContext) throws -> ()
 ) rethrows {
  Task { @Reflection in
   try action(Self.context)
  }
 }

 @discardableResult
 func withContext<A>(
  action: @Reflection @escaping (ModuleContext) throws -> A
 ) rethrows -> A {
  try action(Self.context)
 }

 @discardableResult
 nonisolated func withContext<A: Sendable>(
  action: @Reflection @escaping (ModuleContext) async throws -> A
 ) async rethrows -> A {
  try await action(Self.context)
 }

 nonisolated func callWithContext(
  action: @Reflection @escaping (ModuleContext) async throws -> ()
 ) {
  Task { @Reflection in
   defer { self.callContext() }
   return try await action(Self.context)
  }
 }

 func callWithContext(
  action: @Reflection @escaping (ModuleContext) throws -> ()
 ) rethrows {
  defer { self.callContext() }
  try action(Self.context)
 }

 @discardableResult
 nonisolated func callWithContext<A: Sendable>(
  action: @Reflection @escaping (ModuleContext) async throws -> A
 ) async rethrows -> A {
  defer { Task { @Reflection in self.callContext() } }
  return try await action(Self.context)
 }

 nonisolated func callWithContext(
  to state: ModuleContext.State,
  action: @Reflection @escaping (ModuleContext) async throws -> ()
 ) {
  Task { @Reflection in
   defer { self.callContext(with: state) }
   return try await action(Self.context)
  }
 }

 func callWithContext(
  to state: ModuleContext.State,
  action: @Reflection @escaping (ModuleContext) throws -> ()
 ) rethrows {
  defer { self.callContext(with: state) }
  try action(Self.context)
 }

 @discardableResult
 func callWithContext<A>(
  to state: ModuleContext.State,
  action: @Reflection @escaping (ModuleContext) async throws -> A
 ) async rethrows -> A {
  defer { self.callContext(with: state) }
  return try await action(Self.context)
 }

 #if canImport(Combine) && canImport(SwiftUI)
 @MainActor
 @discardableResult
 func state<A>(
  action: @MainActor @escaping (inout Self) throws -> A
 ) async rethrows -> A {
  let context = await Self.context
  let index = context.index
  var module: Self {
   get { index.element as! Self }
   set { index.element = newValue }
  }
  defer { context.objectWillChange.send() }
  return try action(&module)
 }

 @discardableResult
 mutating func stateWithContext<A>(
  action: @Reflection @escaping (inout Self) throws -> A
 ) rethrows -> A {
  let context = Self.context
  defer {
   context.objectWillChange.send()
   Task {
    context.cache = .empty
    try await context.actor.update()
    context.state = .active
    defer { context.state = .idle }
    try await context.callTasks()
   }
  }
  return try action(&self)
 }

 @discardableResult
 func state<A>(
  action: @Reflection @escaping () throws -> A
 ) rethrows -> A {
  let context = Self.context
  defer { context.objectWillChange.send() }
  return try action()
 }
 #endif
}

#if canImport(Combine) && canImport(SwiftUI)
import Combine

@Reflection(unsafe)
public extension ContextModule {
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}

#elseif os(WASI) && canImport(TokamakCore) && canImport(OpenCombine)
import OpenCombine

@Reflection(unsafe)
public extension ContextModule {
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}
#endif
