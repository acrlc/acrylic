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
 struct Sink<ID: Hashable, Output: Sendable>: Function, @unchecked Sendable {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached = true

  let publisher: AnyPublisher<Output, Never>
  let perform: (_ recievedValue: Output) throws -> ()

  public init<P>(
   _ id: ID,
   priority: TaskPriority? = nil, detached: Bool = true,
   on publisher: P,
   @_implicitSelfCapture perform:
   @escaping (_ recievedValue: P.Output) throws -> ()
  ) where P: Publisher, P.Failure == Never, Output == P.Output {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.publisher = publisher.eraseToAnyPublisher()
   self.perform = perform
  }

  public init<P>(
   priority: TaskPriority? = nil, detached: Bool = true,
   on publisher: P,
   @_implicitSelfCapture perform:
   @escaping (_ recievedValue: Output) throws -> ()
  ) where P: Publisher, P.Failure == Never, Output == P.Output, ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.publisher = publisher.eraseToAnyPublisher()
   self.perform = perform
  }

  public init<P>(
   _ id: ID,
   priority: TaskPriority? = nil, detached: Bool = true,
   on publisher: P,
   @_implicitSelfCapture perform: @escaping () throws -> ()
  ) where P: Publisher, P.Failure == Never, Output == P.Output, Output == Void {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.publisher = publisher.eraseToAnyPublisher()
   self.perform = { _ in try perform() }
  }

  public init<P>(
   priority: TaskPriority? = nil, detached: Bool = true,
   on publisher: P,
   @_implicitSelfCapture perform: @escaping () throws -> ()
  ) where
   P: Publisher, P.Failure == Never, Output == P.Output, Output == Void,
   ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.publisher = publisher.eraseToAnyPublisher()
   self.perform = { _ in try perform() }
  }

  public func callAsFunction() -> AnyCancellable {
   publisher.sink { recievedValue in
    try? perform(recievedValue)
   }
  }

  public struct Async: AsyncFunction,  @unchecked Sendable {
   public var id: ID?
   public var priority: TaskPriority?
   public var detached = true

   let publisher: AnyPublisher<Output, Never>
   let perform: @Sendable (_ recievedValue: Output) async throws -> ()

   public init<P>(
    _ id: ID,
    priority: TaskPriority? = nil, detached: Bool = true,
    on publisher: P,
    @_implicitSelfCapture perform:
    @Sendable @escaping (_ recievedValue: Output) async throws -> ()
   ) where P: Publisher, P.Failure == Never, Output == P.Output {
    self.id = id
    self.priority = priority
    self.detached = detached
    self.publisher = publisher.eraseToAnyPublisher()
    self.perform = perform
   }

   public init<P>(
    priority: TaskPriority? = nil, detached: Bool = true,
    on publisher: P,
    @_implicitSelfCapture perform:
    @Sendable @escaping (_ recievedValue: Output) async throws -> ()
   ) where P: Publisher, P.Failure == Never, Output == P.Output, ID == EmptyID {
    self.priority = priority
    self.detached = detached
    self.publisher = publisher.eraseToAnyPublisher()
    self.perform = perform
   }

   public init<P>(
    _ id: ID,
    priority: TaskPriority? = nil, detached: Bool = true,
    on publisher: P,
    @_implicitSelfCapture perform: @Sendable @escaping () async throws -> ()
   ) where P: Publisher, P.Failure == Never, Output == P.Output,
    Output == Void {
    self.id = id
    self.priority = priority
    self.detached = detached
    self.publisher = publisher.eraseToAnyPublisher()
    self.perform = { _ in try await perform() }
   }

   public init<P>(
    priority: TaskPriority? = nil, detached: Bool = true,
    on publisher: P,
    @_implicitSelfCapture perform: @Sendable @escaping () async throws -> ()
   ) where
    P: Publisher, P.Failure == Never, Output == P.Output, Output == Void,
    ID == EmptyID {
    self.priority = priority
    self.detached = detached
    self.publisher = publisher.eraseToAnyPublisher()
    self.perform = { _ in try await perform() }
   }

   public func callAsFunction() -> AnyCancellable {
    publisher.sink { recievedValue in
     Task(priority: priority) { try await perform(recievedValue) }
    }
   }
  }
 }
}

extension AnyCancellable: @unchecked Sendable {}
#endif
