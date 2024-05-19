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
 @inlinable
 func state(action: @MainActor @escaping () -> ()) {
  objectWillChange.send()
  action()
 }

 @MainActor
 func callState<Result>(action: @Sendable (Self) -> Result) -> Result {
  defer {
   Task { @Reflection in try await Self.context() }
  }
  objectWillChange.send()
  return action(self)
 }

 @MainActor
 func callState(action: @Sendable (Self) -> ()) {
  objectWillChange.send()
  action(self)
  Task { @Reflection in try await Self.context() }
 }

 @MainActor
 func callState(action: @Sendable () -> ()) {
  objectWillChange.send()
  action()
  Task { @Reflection in try await Self.context() }
 }
}
