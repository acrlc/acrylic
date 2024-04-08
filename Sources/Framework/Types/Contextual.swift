public protocol ContextModule: Module {
 init()
}

@_spi(ModuleReflection)
extension ContextModule {
 @inlinable
 unowned static var state: ModuleState {
  Reflection.cacheIfNeeded(Self(), id: Self._mangledName)
 }
 
 @usableFromInline
 static var index: ModuleIndex { state.indices[0] }
}

public extension ContextModule {
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

public extension ContextModule {
 @inlinable
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}

#elseif canImport(OpenCombine)
import OpenCombine
public extension ContextModule {
 @inlinable
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}
#endif
