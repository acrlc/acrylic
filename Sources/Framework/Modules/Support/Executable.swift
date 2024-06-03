// A protocol for running `@main` functions
public protocol MainFunction: Module {
 init()
}

public extension MainFunction {
 static func main() async throws {
  try await Self().callWithContext()
 }
}
