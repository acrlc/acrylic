#if canImport(Command)
@_exported import Command

/// A test that calls `static func main()` with command and context support
public protocol TestsCommand: Tests & AsyncCommand {}
public extension TestsCommand {
 mutating func main() async throws {
  do { try await callAsTestFromContext() }
  catch {
   exit(Int32(error._code))
  }
 }
}
#endif
