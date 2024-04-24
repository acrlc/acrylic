public protocol ContextModule: Module {
 init()
}

@_spi(ModuleReflection)
extension ContextModule {
 @Reflection(unsafe)
 @inlinable
 unowned static var state: ModuleState {
  Reflection.cacheIfNeeded(Self(), id: _mangledName)
 }

 @usableFromInline
 static var index: ModuleIndex { state.indices[0] }
}

public extension ContextModule {
 @usableFromInline
 internal unowned static var context: ModuleContext {
  ModuleContext.cache[index.key]!
 }

 @inlinable
 func callContext() {
  Self.context.callAsFunction()
 }

 @inlinable
 func cancelContext() {
  Task { await Self.context.cancel() }
 }

 @inlinable
 static func updateContext() {
  Task { await context.update() }
 }

 @discardableResult
 @inlinable
 mutating func call<Result>(action: (inout Self) -> Result) -> Result {
  defer { self.callContext() }
  return action(&self)
 }
}

#if canImport(Combine) && canImport(SwiftUI)
import Combine

public extension ContextModule {
 @inlinable
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}

#elseif os(WASI) && canImport(TokamakDOM) && canImport(OpenCombine)
import OpenCombine
public extension ContextModule {
 @inlinable
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}
#endif
