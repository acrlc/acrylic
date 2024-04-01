public protocol StaticModule: Module {
 static var shared: Self { get set }
}

@_spi(ModuleReflection)
extension StaticModule {
 @inlinable
 unowned static var state: ModuleState {
  Reflection.cacheIfNeeded(self)
 }

 @usableFromInline
 static var index: ModuleIndex { state.indices[0][0] }
}

public extension StaticModule {
 unowned static var context: ModuleContext {
  ModuleContext.cache.withLockUnchecked { $0[index.key] }!
 }

 @inlinable
 func callContext() {
  Self.context.callAsFunction()
 }

 @inlinable
 func cancelContext() {
  Self.context.cancel()
 }

 @inlinable
 static func updateContext() {
  context.updateTask = Task { try await context.update() }
 }

 @discardableResult
 @inlinable
 mutating func call<Result>(action: (inout Self) -> Result) -> Result {
  defer { self.callContext() }
  return action(&self)
 }
}

#if canImport(Combine)
import Combine

extension StaticModule {
 @inlinable
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}

#elseif canImport(OpenCombine)
import OpenCombine
extension StaticModule {
 @inlinable
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}
#endif
