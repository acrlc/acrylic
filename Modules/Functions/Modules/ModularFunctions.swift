import Acrylic
import Foundation

public extension Modular {
 /// A namespace for basic modular functions
 /// - Note: This is an organized way to avoid ambiguity
 /// and the requirements for functions is that they match standard functions
 /// but they have the benifit of being modular
 enum Functions {}
}

public typealias ModularFunctions = Modular.Functions
public extension ModularFunctions {
 // Simple but possibly impractical version of the print function
 // When used in modules it can more intuitive functionality
 // TODO: Support
 struct Print: Function {
  public let items: [Any]
  public let separator: String
  public let terminator: String
  public var detached: Bool = true
  public
  init(_ items: Any..., separator: String = " ", terminator: String = "\n") {
   self.items = items
   self.separator = separator
   self.terminator = terminator
  }

  public func callAsFunction() {
   print(items, separator: separator, terminator: terminator)
  }
 }

 struct DebugPrint: Function {
  public let items: [Any]
  public let separator: String
  public let terminator: String
  public var detached: Bool = true

  public
  init(_ items: Any..., separator: String = " ", terminator: String = "\n") {
   self.items = items
   self.separator = separator
   self.terminator = terminator
  }

  public func callAsFunction() {
   debugPrint(
    items, separator: separator, terminator: terminator
   )
  }
 }

 @available(macOS 13, iOS 16, *)
 struct Sleep: Function {
  let duration: Duration
  var microseconds: UInt32?, seconds: UInt32?
  var components: (UInt32?, UInt32?) {
   get { (microseconds, seconds) }
   set {
    microseconds = newValue.0
    seconds = newValue.1
   }
  }

  public init(for duration: Duration) {
   self.duration = duration
   components = duration.sleepMeasure
  }

  public init(nanoseconds: Int64) {
   let duration = Duration.nanoseconds(nanoseconds)
   self.duration = duration
   components = duration.sleepMeasure
  }

  public init(for nanoseconds: Double) {
   let duration = Duration.nanoseconds(Int64(nanoseconds))
   self.duration = duration
   components = duration.sleepMeasure
  }

  public func callAsFunction() {
   if let microseconds {
    usleep(microseconds)
   }
   else if let seconds {
    sleep(seconds)
   }
  }
 }
}

@available(macOS 13, iOS 16, *)
public extension ModularFunctions.Sleep {
 struct Async: AsyncFunction {
  let duration: Duration
  public init(for duration: Duration) {
   self.duration = duration
  }

  public init(nanoseconds: Int64) {
   duration = Duration.nanoseconds(nanoseconds)
  }

  public init(for nanoseconds: Double) {
   duration = Duration.nanoseconds(Int64(nanoseconds))
  }

  public func callAsyncFunction() async throws {
   try await Task.sleep(for: duration)
  }
 }
}

public extension Module {
 typealias Functions = Modular.Functions
 typealias Print = Modular.Functions.Print
 typealias DebugPrint = Modular.Functions.DebugPrint
 @available(macOS 13, iOS 16, *)
 typealias Sleep = Modular.Functions.Sleep
}

#if canImport(Shell)
import Shell

public extension ModularFunctions {
 struct Echo: Function {
  public let items: [Any]
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
   self.items = items
   self.color = color
   self.background = background
   self.style = style
   self.separator = separator
   self.terminator = terminator
  }

  public func callAsFunction() {
   echo(
    items,
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
