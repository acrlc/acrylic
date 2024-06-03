#if canImport(Command)
@_exported import Command

/// A module that calls `static func main()` with command and context support
public protocol CommandModule: Module & AsyncCommand {}
public extension CommandModule {
 mutating func main() async throws {
  do { try await callWithContext() }
  catch {
   exit(Int32(error._code))
  }
 }
}
#endif
