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
 func callState<Result>(action: @Sendable (Self) -> Result) -> Result {
  defer { Task { @Reflection in try await Self.callContext() } }
  objectWillChange.send()
  return action(self)
 }
}
