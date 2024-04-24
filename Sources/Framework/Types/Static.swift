public protocol StaticModule: Module {
 static var shared: Self { get set }
}

@_spi(ModuleReflection)
extension StaticModule {
 @Reflection(unsafe)
 @inlinable
 unowned static var state: ModuleState {
  Reflection.cacheIfNeeded(self)
 }

 @usableFromInline
 static var index: ModuleIndex { state.indices[0] }
}

public extension StaticModule {
 unowned static var context: ModuleContext { state.mainContext }

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

public extension StaticModule {
 @inlinable
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}
#elseif os(WASI) && canImport(TokamakDOM) && canImport(OpenCombine)
import OpenCombine
extension StaticModule {
 @inlinable
 var contextWillChange: ModuleContext.ObjectWillChangePublisher {
  Self.context.objectWillChange
 }
}
#endif
