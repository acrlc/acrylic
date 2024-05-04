public protocol StaticModule: Module {
 static var shared: Self { get set }
}

@_spi(ModuleReflection)
@Reflection
public extension StaticModule {
 static var state: ModuleState {
  Reflection.cacheIfNeeded(
   id: _mangledName, module: shared, stateType: ModuleState.self
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
}

public extension StaticModule {
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
 
 func callContext() {
  Task {
   try await Self.callContext()
  }
 }
 
 func callContext(with state: ModuleContext.State) {
  Task {
   try await Self.callContext(with: state)
  }
 }
 
 func cancelContext() {
  Task {
   await Self.cancelContext()
  }
 }

 func cancelContext(with state: ModuleContext.State) {
  Task {
   await Self.cancelContext(with: state)
  }
 }
 
 func updateContext() {
  Task {
   try await Self.updateContext()
  }
 }
 
 func updateContext(with state: ModuleContext.State) {
  Task {
   try await Self.updateContext(with: state)
  }
 }
 
 @discardableResult
 mutating func call<Result>( action: (inout Self) -> Result) -> Result {
  defer { self.callContext() }
  return action(&self)
 }

 @discardableResult
 mutating func call<Result>(
  with state: ModuleContext.State, action: (inout Self) -> Result
 ) -> Result {
  defer { self.callContext(with: state) }
  return action(&self)
 }
}

#if canImport(Combine) && canImport(SwiftUI)
import Combine

@Reflection
public extension StaticModule {
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}

#elseif os(WASI) && canImport(TokamakDOM) && canImport(OpenCombine)
import OpenCombine

@Reflection
extension StaticModule {
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}
#endif
