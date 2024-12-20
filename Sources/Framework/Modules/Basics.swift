public extension Modular {
 /// Aligns or tags the attributes of every module contained within the group
 struct Group<ID: Hashable, Results: Module>: Module, @unchecked Sendable {
  public var id: ID?
  @Modular
  public var results: () -> Results

  public var void: Modules { results() }

  public init(
   _ id: ID,
   @Modular @_implicitSelfCapture results: @escaping () -> Results
  ) {
   self.id = id
   self.results = results
  }

  public init(
   @Modular @_implicitSelfCapture results: @escaping () -> Results
  ) where ID == EmptyID {
   self.results = results
  }

  public init(id: ID?, array: Modules) where Results == Modules {
   self.id = id
   results = { array }
  }

  public init(array: Modules) where Results == Modules, ID == EmptyID {
   results = { array }
  }
 }

 /// Maps the results of iterating over a sequence as a single group of modules
 struct Map<ID: Hashable, Elements, Result>: Module, @unchecked Sendable
  where Elements: Sequence, Result: Module {
  public var id: ID?
  public var elements: Elements
  @Modular
  public var result: (Elements.Element) -> Result

  /// - Note: This automatically converts the map into a group with the same id
  public var void: some Module {
   Group(id: id, array: elements.map { result($0) })
  }

  public init(
   _ id: ID, _ elements: Elements,
   @Modular @_implicitSelfCapture result: @escaping (Elements.Element) -> Result
  ) {
   self.id = id
   self.elements = elements
   self.result = result
  }

  public init(
   _ elements: Elements,
   @Modular @_implicitSelfCapture result: @escaping (Elements.Element) -> Result
  ) where ID == EmptyID {
   self.elements = elements
   self.result = result
  }
 }
}

public extension Module {
 typealias Group = Modular.Group
 typealias Map = Modular.Map
}

// MARK: - Extensions
import protocol Core.ExpressibleAsEmpty
import protocol Core.ExpressibleAsStart
import protocol Core.Infallible

extension Range: @retroactive ExpressibleAsEmpty
where Bound: ExpressibleAsStart {
 public static var empty: Self { Self(uncheckedBounds: (.start, .start)) }
}

extension ClosedRange: @retroactive ExpressibleAsEmpty
where Bound: ExpressibleAsStart {
 public static var empty: Self { Self(uncheckedBounds: (.start, .start)) }
}

public extension Module.Map where Elements == Range<Int> {
 init(
  _ id: ID,
  count: Int,
  @Modular @_implicitSelfCapture result: @escaping (Elements.Element) -> Result
 ) {
  self.id = id
  elements = 0 ..< count
  self.result = result
 }

 init(
  count: Int,
  @Modular @_implicitSelfCapture result: @escaping (Elements.Element) -> Result
 ) where ID == EmptyID {
  elements = 0 ..< count
  self.result = result
 }

 init(
  _ id: ID,
  count: Int,
  @Modular @_implicitSelfCapture result: @escaping () -> Result
 ) {
  self.id = id
  elements = 0 ..< count
  self.result = { _ in result() }
 }

 init(
  count: Int,
  @Modular @_implicitSelfCapture result: @escaping () -> Result
 ) where ID == EmptyID {
  id = nil
  elements = 0 ..< count
  self.result = { _ in result() }
 }
}
