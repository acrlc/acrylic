import Foundation

/// A module that performs a function when called
public protocol Function: Module {
 associatedtype Output: Sendable
 typealias Priority = TaskPriority
 var priority: Priority? { get set }
 var detached: Bool { get set }
 @inlinable
 @discardableResult
 func callAsFunction() async throws -> Output
}

public extension Function {
 @_disfavoredOverload
 @inlinable
 var priority: Priority? { get { nil } set {} }
 @_disfavoredOverload
 @inlinable
 var detached: Bool { get { false } set {} }
}

public extension Function where Output == Never {
 @_disfavoredOverload
 @inlinable
 func callAsFunction() -> Never {
  fatalError("\(_type) '\(Self.self)' should define \(#function)")
 }
}

public extension Function where VoidFunction == Empty {
 @_disfavoredOverload
 var void: Empty { Empty() }
}

/// A module that explicitly performs an asynchronous function
public protocol AsyncFunction: Module {
 associatedtype Output: Sendable
 typealias Priority = TaskPriority
 var priority: Priority? { get set }
 var detached: Bool { get set }
 @inlinable
 @discardableResult
 func callAsyncFunction() async throws -> Output
}

public extension AsyncFunction {
 @_disfavoredOverload
 @inlinable
 var priority: Priority? { get { nil } set {} }
 @_disfavoredOverload
 @inlinable
 var detached: Bool { get { false } set {} }
 @_disfavoredOverload
 @inlinable
 func callAsFunction() async throws -> Output {
  try await callAsyncFunction()
 }
}

extension AsyncFunction where Output == Never {
 @_disfavoredOverload
 @inlinable
 func callAsyncFunction() async throws -> Never {
  fatalError("\(_type) '\(Self.self)' should define \(#function)")
 }
}

public extension AsyncFunction where VoidFunction == Empty {
 @_disfavoredOverload
 var void: Empty { Empty() }
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
 @inlinable
 func callAsFunction() async throws -> [Sendable] {
  var results: [Sendable] = []
  for module in self {
   if let modules = module as? Modules {
    try await results.append(modules.callAsFunction())
   } else if let task = module as? any AsyncFunction {
    try await results.append(task.callAsyncFunction())
   } else if let task = module as? any Function {
    try await results.append(task.callAsFunction())
   } else {
    try await results.append(module.callAsFunction())
   }
  }
  return results
 }
}

/// A protocol for runing `@main` functions
public protocol MainFunction: Function {
 init()
 @inlinable
 func main() throws
}

public extension MainFunction where Output == Never {
 @_disfavoredOverload
 @inlinable
 func main() async throws {
  if avoid {
   try await (self as? Modules)?.callAsFunction()
  } else {
   try await void.callAsFunction()
  }
 }
}

public extension MainFunction {
 @_disfavoredOverload
 @inlinable
 func main() async throws { try await callAsFunction() }
}

public extension MainFunction {
 @inlinable
 static func main() throws {
  let function = self.init()
  try function.main()
 }
}

// MARK: - Modules
public extension Modular {
 struct Perform<ID: Hashable, Output>: Function {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let action: () throws -> Output

  public init(
   _ id: ID,
   priority: Priority? = nil,
   detached: Bool = false,
   action: @escaping () throws -> Output
  ) {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.action = action
  }

  public init(
   priority: Priority? = nil,
   detached: Bool = false,
   action: @escaping () throws -> Output
  ) where ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.action = action
  }

  public func callAsFunction() throws -> Output {
   try action()
  }
 }

 struct Repeat<ID: Hashable>: Function {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let perform: () throws -> Bool

  public init(
   _ id: ID,
   priority: TaskPriority? = nil,
   detached: Bool = false,
   perform: @escaping () throws -> Bool
  ) {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.perform = perform
  }

  public init(
   priority: TaskPriority? = nil,
   detached: Bool = false,
   perform: @escaping () throws -> Bool
  ) where ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.perform = perform
  }

  public func callAsFunction() throws {
   while try perform() { continue }
  }
 }

 struct Loop<ID: Hashable>: Function {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let perform: () throws -> ()

  public init(
   _ id: ID,
   priority: TaskPriority? = nil,
   detached: Bool = false,
   perform: @escaping () throws -> ()
  ) {
   self.id = id
   self.priority = priority
   self.detached = detached
   self.perform = perform
  }

  public init(
   priority: TaskPriority? = nil,
   detached: Bool = false,
   perform: @escaping () throws -> ()
  ) where ID == EmptyID {
   self.priority = priority
   self.detached = detached
   self.perform = perform
  }

  public func callAsFunction() throws {
   repeat { try perform() } while true
  }
 }
}

public extension Modular.Perform {
 struct Async: AsyncFunction {
  public var id: ID?
  public var priority: Priority?
  public let detached: Bool
  public let action: () async throws -> Output

  public func callAsyncFunction() async throws -> Output {
   try await action()
  }
 }
}

public extension Modular.Perform.Async {
 init(
  _ id: ID,
  priority: Priority? = nil,
  detached: Bool = false,
  action: @escaping () async throws -> Output
 ) {
  self.id = id
  self.priority = priority
  self.detached = detached
  self.action = action
 }

 init(
  priority: Priority? = nil,
  detached: Bool = false,
  action: @escaping () async throws -> Output
 ) where ID == EmptyID {
  self.priority = priority
  self.detached = detached
  self.action = action
 }

 init(
  _ id: ID,
  priority: Priority? = nil,
  detached: Bool = false,
  main: @escaping @MainActor () throws -> Output
 ) {
  self.init(
   id, priority: priority, detached: detached,
   action: { @MainActor in try main() }
  )
 }

 init(
  priority: Priority? = nil,
  detached: Bool = false,
  main: @escaping @MainActor () throws -> Output
 ) where ID == EmptyID {
  self.init(
   priority: priority, detached: detached,
   action: { @MainActor in try main() }
  )
 }
}

public extension Modular.Repeat {
 struct Async: AsyncFunction {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let perform: () async throws -> Bool
  public func callAsyncFunction() async throws {
   while try await perform() { continue }
  }
 }
}

public extension Modular.Repeat.Async {
 init(
  _ id: ID,
  priority: TaskPriority? = nil,
  detached: Bool = false,
  perform: @escaping () async throws -> Bool
 ) {
  self.id = id
  self.priority = priority
  self.detached = detached
  self.perform = perform
 }

 init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  perform: @escaping () async throws -> Bool
 ) where ID == EmptyID {
  self.priority = priority
  self.detached = detached
  self.perform = perform
 }
}

public extension Modular.Loop {
 struct Async: AsyncFunction {
  public var id: ID?
  public var priority: TaskPriority?
  public var detached: Bool = false
  public let perform: () async throws -> ()
  public func callAsyncFunction() async throws {
   repeat { try await perform() } while true
  }
 }
}

public extension Modular.Loop.Async {
 init(
  _ id: ID,
  priority: TaskPriority? = nil,
  detached: Bool = false,
  perform: @escaping () async throws -> ()
 ) {
  self.id = id
  self.priority = priority
  self.detached = detached
  self.perform = perform
 }

 init(
  priority: TaskPriority? = nil,
  detached: Bool = false,
  perform: @escaping () async throws -> ()
 ) where ID == EmptyID {
  self.priority = priority
  self.detached = detached
  self.perform = perform
 }
}

public extension Module {
 typealias Perform = Modular.Perform
 typealias Repeat = Modular.Repeat
 typealias Loop = Modular.Loop
}

public extension Modular.Group where Results == [any Module] {
 func detached(_ detached: Bool) -> Self {
  Self(
   id: id,
   array:
   results().map {
    if var asyncFunction = $0 as? any AsyncFunction {
     asyncFunction.detached = detached
     return asyncFunction
    } else if var function = $0 as? any Function {
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
  @Modular results: @escaping () -> Results
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
  @Modular results: @escaping () -> Results
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

/* TODO: Enable function that return results. Maybe, send those results with a property wrapper, keyPath, or built in observeration handler */
