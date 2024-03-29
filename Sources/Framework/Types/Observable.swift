#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#else
#error("Cannot import Combine framework")
#endif

public protocol ObservableModule: StaticModule, ObservableObject
 where ObjectWillChangePublisher == ObservableObjectPublisher {}

public extension ObservableModule {
 @MainActor
 @inlinable
 func state(action: @MainActor @escaping (Self) -> ()) {
  objectWillChange.send()
  action(self)
 }

 @MainActor
 @discardableResult
 @inlinable
 func callState<Result>(action: (Self) -> Result) -> Result {
  defer { self.callContext() }
  objectWillChange.send()
  return action(self)
 }
}
