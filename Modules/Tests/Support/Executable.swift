import func Foundation.exit
/// A test that calls `static func main()` with context support
public protocol StaticTests: Tests {
 static func main() async
}

public extension StaticTests {
 @_disfavoredOverload
 static func main() async {
  //   load descriptive modules from context
  var copy = Self()
  do { try await copy.callAsTestFromContext() }
  catch { exit(Int32(error._code)) }
 }
}

