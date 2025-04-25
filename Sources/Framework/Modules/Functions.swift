import Foundation

/// A module that performs a function when called
public protocol Function: Detachable, Module {
 associatedtype Output
 typealias Priority = TaskPriority
 var priority: Priority? { get set }
 var detached: Bool { get set }
 @inlinable
 @discardableResult
 func callAsFunction() throws -> Output
}

public extension Function {
 @_disfavoredOverload
 @inlinable
 var priority: Priority? { get { nil } set {} }
 @_disfavoredOverload
 @inlinable
 var detached: Bool { get { false } set {} }
 func detached(priority: TaskPriority? = nil, _ detached: Bool = true) -> Self {
  var copy = self
  if let priority {
   copy.priority = priority
  }
  copy.detached = detached
  return copy
 }
}

public extension Function where Output == Never {
 @_disfavoredOverload
 func callAsFunction() -> Never {
  fatalError("\(_type) '\(Self.self)' should define \(#function)")
 }
}

public extension Function where VoidFunction == EmptyModule {
 @_disfavoredOverload
 var void: EmptyModule { EmptyModule() }
}

/// A module that explicitly performs an asynchronous function
public protocol AsyncFunction: Detachable, Module {
 associatedtype Output: Sendable
 typealias Priority = TaskPriority
 var priority: Priority? { get set }
 var detached: Bool { get set }
 @inlinable
 @discardableResult
 func callAsFunction() async throws -> Output
}

public extension AsyncFunction {
 @_disfavoredOverload
 @inlinable
 var priority: Priority? { get { nil } set {} }
 @_disfavoredOverload
 @inlinable
 var detached: Bool { get { false } set {} }
 func detached(priority: TaskPriority? = nil, _ detached: Bool = true) -> Self {
  var copy = self
  if let priority {
   copy.priority = priority
  }
  copy.detached = detached
  return copy
 }
}

public extension AsyncFunction where Output == Never {
 @_disfavoredOverload
 func callAsFunction() async throws -> Never {
  fatalError("\(_type) '\(Self.self)' should define \(#function)")
 }
}

public extension AsyncFunction where VoidFunction == EmptyModule {
 @_disfavoredOverload
 var void: EmptyModule { EmptyModule() }
}

/* TODO: incorporate with modifiers
 /// A ``Function`` that can resolved asynchronously
 public protocol AsyncResolvable: Function where Async.Output == Self.Output {
  associatedtype Async: AsyncFunction
 }

 public protocol AsyncConvertible: AsyncResolvable {
  /// Converts the `Self` to the asynchronous counterpart
  func async() -> Async
 }
 */

/***
 Call modules as functions when used without reflection
 */
public extension Modules {
 @_disfavoredOverload
 @discardableResult
 func callAsFunction() async throws -> [Sendable] {
  var results: [Sendable] = []
  var detached = [Task<Sendable, Error>]()
  for module in self {
   if let modules = module as? Modules {
    try await results.append(modules.callAsFunction())
   } else if let task = module as? any AsyncFunction {
    if task.detached {
     detached.append(
      Task.detached(priority: task.priority) {
       try await task.callAsFunction()
      }
     )
    } else {
     try await results.append(task.callAsFunction())
    }
   } else if let task = module as? any Function {
    if task.detached {
     detached.append(
      Task.detached(priority: task.priority) {
       try task.callAsFunction()
      }
     )
    } else {
     try results.append(task.callAsFunction())
    }
   } else if !module.avoid {
    try await results.append((module.void as! Modules).callAsFunction())
   }
  }

  for task in detached {
   try await task.wait()
  }

  return results
 }
}

// MARK: - Modules
public extension Modular {
 struct Perform<ID: Hashable, Output: Sendable>: Function, @unchecked Sendable {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let action: () throws -> Output

  public init(
   _ id: ID,
   priority: Priority? = nil,
   detached: Bool = false,
   @_implicitSelfCapture action: @escaping () throws -> Output
  ) {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.action = action
  }

  public init(
   priority: Priority? = nil,
   detached: Bool = false,
   @_implicitSelfCapture action: @escaping () throws -> Output
  ) where ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.action = action
  }

  public static func detached(
   _ id: ID,
   priority: TaskPriority? = nil,
   _ detached: Bool = true,
   @_implicitSelfCapture action: @escaping () throws -> Output
  ) -> Self {
   self.init(id, priority: priority, detached: detached, action: action)
  }

  public static func detached(
   priority: TaskPriority? = nil,
   _ detached: Bool = true,
   @_implicitSelfCapture action: @escaping () throws -> Output
  ) -> Self where ID == EmptyID {
   self.init(priority: priority, detached: detached, action: action)
  }

  public func callAsFunction() throws -> Output {
   try action()
  }
 }

 struct Repeat<ID: Hashable>: Function, @unchecked Sendable {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let perform: () throws -> Bool

  public init(
   _ id: ID,
   priority: TaskPriority? = nil,
   detached: Bool = false,
   @_implicitSelfCapture perform: @escaping () throws -> Bool
  ) {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.perform = perform
  }

  public init(
   priority: TaskPriority? = nil,
   detached: Bool = false,
   @_implicitSelfCapture perform: @escaping () throws -> Bool
  ) where ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.perform = perform
  }

  public static func detached(
   _ id: ID,
   priority: TaskPriority? = nil,
   _ detached: Bool = true,
   @_implicitSelfCapture perform: @escaping () throws -> Bool
  ) -> Self {
   self.init(id, priority: priority, detached: detached, perform: perform)
  }

  public static func detached(
   priority: TaskPriority? = nil,
   _ detached: Bool = true,
   @_implicitSelfCapture perform: @escaping () throws -> Bool
  ) -> Self where ID == EmptyID {
   self.init(priority: priority, detached: detached, perform: perform)
  }

  public func callAsFunction() throws {
   while try perform() {
    continue
   }
  }
 }

 struct Loop<ID: Hashable>: Function, @unchecked Sendable {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let perform: () throws -> Void

  public init(
   _ id: ID,
   priority: TaskPriority? = nil,
   detached: Bool = false,
   @_implicitSelfCapture perform: @escaping () throws -> Void
  ) {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.perform = perform
  }

  public init(
   priority: TaskPriority? = nil,
   detached: Bool = false,
   @_implicitSelfCapture perform: @escaping () throws -> Void
  ) where ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.perform = perform
  }

  public static func detached(
   _ id: ID,
   priority: TaskPriority? = nil,
   _ detached: Bool = true,
   @_implicitSelfCapture perform: @escaping () throws -> Void
  ) -> Self {
   self.init(id, priority: priority, detached: detached, perform: perform)
  }

  public static func detached(
   priority: TaskPriority? = nil,
   _ detached: Bool = true,
   @_implicitSelfCapture perform: @escaping () throws -> Void
  ) -> Self where ID == EmptyID {
   self.init(priority: priority, detached: detached, perform: perform)
  }

  public func callAsFunction() throws {
   repeat {
    try perform()
   } while true
  }
 }
}

public extension Modular.Perform {
 struct Async: AsyncFunction, @unchecked Sendable {
  public var id: ID?
  public var priority: Priority?
  public var detached: Bool
  public let action: @isolated(any) @Sendable () async throws -> Output

  public func callAsFunction() async throws -> Output {
   try await action()
  }
 }
}

public extension Modular.Perform.Async {
 init(
  _ id: ID,
  priority: Priority? = nil,
  detached: Bool = false,
  @_implicitSelfCapture action: @isolated(any) @Sendable @escaping () async throws -> Output
 ) {
  self.id = id
  self.priority = priority
  self.detached = detached
  self.action = action
 }

 init(
  priority: Priority? = nil,
  detached: Bool = false,
  @_implicitSelfCapture action: @isolated(any) @Sendable @escaping () async throws -> Output
 ) where ID == EmptyID {
  self.priority = priority
  self.detached = detached
  self.action = action
 }

 @_disfavoredOverload
 init(
  _ id: ID,
  priority: Priority? = nil,
  detached: Bool = false,
  @_implicitSelfCapture main: @Sendable @escaping @MainActor () throws -> Output
 ) {
  self.init(
   id, priority: priority, detached: detached,
   action: { @MainActor in try main() }
  )
 }

 @_disfavoredOverload
 init(
  priority: Priority? = nil,
  detached: Bool = false,
  @_implicitSelfCapture main: @Sendable @escaping @MainActor () throws -> Output
 ) where ID == EmptyID {
  self.init(
   priority: priority, detached: detached,
   action: { @MainActor in try main() }
  )
 }

 static func detached(
  _ id: ID,
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  @_implicitSelfCapture action: @isolated(any) @Sendable @escaping () async throws -> Output
 ) -> Self {
  self.init(id, priority: priority, detached: detached, action: action)
 }

 static func detached(
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  @_implicitSelfCapture action: @isolated(any) @Sendable @escaping () async throws -> Output
 ) -> Self where ID == EmptyID {
  self.init(priority: priority, detached: detached, action: action)
 }
}

public extension Modular.Repeat {
 struct Async: AsyncFunction, @unchecked Sendable {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let perform: @isolated(any) @Sendable () async throws -> Bool
  public func callAsFunction() async throws {
   while try await perform() {
    continue
   }
  }
 }
}

public extension Modular.Repeat.Async {
 init(
  _ id: ID,
  priority: TaskPriority? = nil,
  detached: Bool = false,
  @_implicitSelfCapture perform: @isolated(any) @Sendable @escaping () async throws -> Bool
 ) {
  self.id = id
  self.priority = priority
  self.detached = detached
  self.perform = perform
 }

 init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  @_implicitSelfCapture perform: @isolated(any) @Sendable @escaping () async throws -> Bool
 ) where ID == EmptyID {
  self.priority = priority
  self.detached = detached
  self.perform = perform
 }

 static func detached(
  _ id: ID,
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  @_implicitSelfCapture perform: @isolated(any) @Sendable @escaping () async throws -> Bool
 ) -> Self {
  self.init(id, priority: priority, detached: detached, perform: perform)
 }

 static func detached(
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  @_implicitSelfCapture perform: @isolated(any) @Sendable @escaping () async throws -> Bool
 ) -> Self where ID == EmptyID {
  self.init(priority: priority, detached: detached, perform: perform)
 }
}

public extension Modular.Loop {
 struct Async: AsyncFunction, @unchecked Sendable {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let perform: @Sendable () async throws -> Void
  public func callAsFunction() async throws {
   repeat {
    try await perform()
   } while true
  }
 }
}

public extension Modular.Loop.Async {
 init(
  _ id: ID,
  priority: TaskPriority? = nil,
  detached: Bool = false,
  @_implicitSelfCapture perform: @Sendable @escaping () async throws -> Void
 ) {
  self.id = id
  self.priority = priority
  self.detached = detached
  self.perform = perform
 }

 init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  @_implicitSelfCapture perform: @Sendable @escaping () async throws -> Void
 ) where ID == EmptyID {
  self.priority = priority
  self.detached = detached
  self.perform = perform
 }

 static func detached(
  _ id: ID,
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  @_implicitSelfCapture perform: @Sendable @escaping () async throws -> Void
 ) -> Self {
  self.init(id, priority: priority, detached: detached, perform: perform)
 }

 static func detached(
  priority: TaskPriority? = nil,
  _ detached: Bool = true,
  @_implicitSelfCapture perform: @Sendable @escaping () async throws -> Void
 ) -> Self where ID == EmptyID {
  self.init(priority: priority, detached: detached, perform: perform)
 }
}

public extension Module {
 typealias Perform = Modular.Perform
 typealias Repeat = Modular.Repeat
 typealias Loop = Modular.Loop
}

public extension Modular.Group where Results == [any Module] {
 func detached(priority: TaskPriority? = nil, _ detached: Bool = true) -> Self {
  Self(
   id: id,
   array:
   results().map {
    if var asyncFunction = $0 as? any AsyncFunction {
     if let priority {
      asyncFunction.priority = priority
     }
     asyncFunction.detached = detached
     return asyncFunction
    } else if var function = $0 as? any Function {
     if let priority {
      function.priority = priority
     }
     function.detached = detached
     return function
    }
    return $0
   }
  )
 }

 func priority(_ priority: TaskPriority? = nil) -> Self {
  Self(
   id: id,
   array:
   results().map {
    if var asyncFunction = $0 as? any AsyncFunction {
     asyncFunction.priority = priority
     return asyncFunction
    } else if var function = $0 as? any Function {
     function.priority = priority
     return function
    }
    return $0
   }
  )
 }

 init(
  _ id: ID,
  priority: TaskPriority? = nil,
  detached: Bool = false,
  @Modular @_implicitSelfCapture results: @escaping () -> Results
 ) {
  self.init(
   id: id,
   array:
   results().map {
    if var asyncFunction = $0 as? any AsyncFunction {
     asyncFunction.priority = priority
     asyncFunction.detached = detached
     return asyncFunction
    } else if var function = $0 as? any Function {
     function.priority = priority
     function.detached = detached
     return function
    }
    return $0
   }
  )
 }

 init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  @Modular @_implicitSelfCapture results: @escaping () -> Results
 ) where ID == EmptyID {
  self.init(
   array:
   results().map {
    if var asyncFunction = $0 as? any AsyncFunction {
     asyncFunction.priority = priority
     asyncFunction.detached = detached
     return asyncFunction
    } else if var function = $0 as? any Function {
     function.priority = priority
     function.detached = detached
     return function
    }
    return $0
   }
  )
 }
}

// MARK: Protocols
public protocol Detachable {
 var detached: Bool { get set }
}
