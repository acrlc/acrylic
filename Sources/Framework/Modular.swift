@resultBuilder
public enum Modular {
 public typealias Component = any Module
 public typealias Components = Modules
 public static func buildBlock(_ components: Component...) -> Components {
  components._flattened
 }

 public static func buildArray(_ components: [Component]) -> Components {
  components._flattened
 }

 @Modular
 public static func buildEither(first: some Module) -> Components {
  first
 }

 @Modular
 public static func buildEither(second: Component?) -> Components {
  second == nil ? .empty : [second.unsafelyUnwrapped]
 }

 public static func buildOptional(_ optional: Component?) -> Components {
  optional == nil ? .empty : [optional.unsafelyUnwrapped]
 }

 @Modular
 public static func buildLimitedAvailability(
  _ component: some Module
 ) -> Components {
  component
 }

 public static func buildFinalResult(_ components: Component...) -> Components {
  components._flattened
 }
}

// MARK: - Module Extensions
public typealias Modules = [any Module]
extension Modules: @retroactive Identifiable {}
extension Modules: Module {
 public typealias Body = Never
 public var _compact: Self {
  compactMap {
   if let optionals = $0 as? Modules? {
    switch optionals {
    case .none: nil
    case .some(let modules): modules
    }
   } else {
    $0
   }
  }
 }

 public var _flattened: Self {
  var results: Modules = .empty
  for module in self {
   if let modules = (module as? Self)?._compact, modules.notEmpty {
    for module in modules where module.notEmpty {
     results.append(module)
    }
   } else if module.notEmpty {
    results.append(module)
   }
  }
  return results._compact
 }

 var isEmpty: Bool { allSatisfy(\.isEmpty) }
 @usableFromInline
 var notEmpty: Bool { !isEmpty }
}
