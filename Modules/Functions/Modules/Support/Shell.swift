#if canImport(Shell)
@_exported import Shell

public extension ModularFunctions {
 struct Echo: Function {
  public let items: [String]
  public let color: Chalk.Color?
  public let background: Chalk.Color?
  public let style: Chalk.Style?
  public let separator: String
  public let terminator: String
  public var detached: Bool = true
  public
  init(
   _ items: Any...,
   color: Chalk.Color? = nil,
   background: Chalk.Color? = nil,
   style: Chalk.Style? = nil,
   separator: String = " ", terminator: String = "\n"
  ) {
   self.items = items.map(String.init(describing:))
   self.color = color
   self.background = background
   self.style = style
   self.separator = separator
   self.terminator = terminator
  }
  
  public func callAsFunction() {
   echo(
    items as [Any],
    color: color, background: background, style: style,
    separator: separator,
    terminator: terminator
   )
  }
 }
}

public extension Module {
 typealias Echo = Modular.Functions.Echo
}
#endif
