#if canImport(Combine) || canImport(OpenCombine)
#if canImport(Combine)
import Combine
#elseif canImport(OpenCombine)
import OpenCombine
#endif

public enum CombineModules {}
public extension Module {
 typealias Combine = CombineModules
}

public extension CombineModules {
 struct Sink<ID: Hashable, Value>: Function {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached = true

  let publisher: Published<Value>.Publisher
  let perform: (_ newValue: Value) throws -> ()

  public init(
   _ id: ID,
   priority: TaskPriority? = nil, detached: Bool = true,
   on publisher: Published<Value>.Publisher,
   @_implicitSelfCapture perform:
   @escaping (_ recievedValue: Value) throws -> ()
  ) {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.publisher = publisher
   self.perform = perform
  }

  public init(
   priority: TaskPriority? = nil, detached: Bool = true,
   on publisher: Published<Value>.Publisher,
   @_implicitSelfCapture perform:
   @escaping (_ recievedValue: Value) throws -> ()
  ) where ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.publisher = publisher
   self.perform = perform
  }

  public func callAsFunction() -> AnyCancellable {
   publisher.sink { recievedValue in
    try? perform(recievedValue)
   }
  }

  public struct Async: AsyncFunction {
   public var id: ID?
   public var priority: TaskPriority?
   public var detached = true

   let publisher: Published<Value>.Publisher
   let perform: @Sendable (_ recievedValue: Value) async throws -> ()

   public init(
    _ id: ID, priority: TaskPriority? = nil, detached: Bool = true,
    on publisher: Published<Value>.Publisher,
    @_implicitSelfCapture perform:
    @Sendable @escaping (_ recievedValue: Value) async throws -> ()
   ) {
    self.id = id
    self.priority = priority
    self.detached = detached
    self.publisher = publisher
    self.perform = perform
   }

   public init(
    priority: TaskPriority? = nil, detached: Bool = true,
    on publisher: Published<Value>.Publisher,
    @_implicitSelfCapture perform:
    @Sendable @escaping (_ recievedValue: Value) async throws -> ()
   ) where ID == EmptyID {
    self.priority = priority
    self.detached = detached
    self.publisher = publisher
    self.perform = perform
   }

   public func callAsFunction() -> AnyCancellable {
    publisher.sink { recievedValue in
     Task(priority: priority) { try await perform(recievedValue) }
    }
   }
  }
 }
}

#endif
