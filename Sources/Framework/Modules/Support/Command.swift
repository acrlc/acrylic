#if canImport(Command)
@_exported import Command

/// A module that calls `static func main()` with command and context support
public typealias CommandModule = Module & AsyncCommand
public extension Module where Self: AsyncCommand {
 func main() async throws {
  do { try await callWithContext() }
  catch {
   exit(error)
  }
 }
}
#endif
