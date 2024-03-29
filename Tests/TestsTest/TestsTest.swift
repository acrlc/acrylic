import Benchmarks
import Tests
import XCTest

final class TestsTest: XCTestCase {
 func testAssert() async throws {
  // test assertion
  try await (Assertion(true)).callAsyncFunction()
  await XCTAssertThrow(
   Assertion(false).callAsyncFunction,
   message: "Asserted condition wasn't met"
  )

  try await Assertion("Testing", ==, "Testing").callAsyncFunction()
  try await Assertion("Testing", !=, "Passed").callAsyncFunction()
  try await Assertion(0, ==, 0).callAsyncFunction()
  try await Assertion(0, ==) { 0 }.callAsyncFunction()
  try await Assertion(1, >) { 0 }.callAsyncFunction()
  try await Assertion(-1, <) { 0 }.callAsyncFunction()
  try await Assertion(1, >=) { 0 }.callAsyncFunction()
  try await Assertion(-1, <=) { 0 }.callAsyncFunction()

  await XCTAssertThrow(
   Assertion(0, !=, 0).callAsyncFunction,
   message:
   """
   \n\tExpected condition from \(0, style: .underlined) \
   to \(0, style: .underlined) wasn't met
   """
  )
  await XCTAssertThrow(
   Assertion(1, >, 99).callAsyncFunction,
   message:
   """
   \n\tExpected condition from \(1, style: .underlined) \
   to \(99, style: .underlined) wasn't met
   """
  )

  /// test Identity
  try await (Identity(false) == false).callAsyncFunction()
  try await (Identity(true) != false).callAsyncFunction()
  try await (Identity(-1) < 0).callAsyncFunction()
  try await (Identity(1) > 0).callAsyncFunction()
  try await (Identity(-1) <= 0).callAsyncFunction()
  try await (Identity(1) >= 0).callAsyncFunction()

  await XCTAssertThrow(
   (Identity(1) > 99).callAsyncFunction,
   message:
   """
   \n\tExpected condition from \(1, style: .underlined) \
   to \(99, style: .underlined) wasn't met
   """
  )

  // test overrides
  await XCTAssertThrow(
   Assertion(false, { condition, _ in condition }, {}).callAsyncFunction,
   message: "Asserted condition wasn't met"
  )
 }

 func testModule() async throws {
  try await TestModule().callAsTest()
 }
}

extension XCTest {
 func XCTAssertThrow(
  _ closure: @escaping () async throws -> some Any,
  message: String? = nil
 ) async {
  do {
   _ = try await closure()
   XCTFail("Assertion to throw failed")
  } catch {
   if let message {
    XCTAssertEqual(error.message, message)
   }
  }
 }
}

struct TestModule: Tests {
 var tests: some Testable {
  Assert("Basic Assertion", true)
  Identity("Basic Identity", "Hello") != "World!"
  Benchmarks("Sleep") {
   Measure.Async(iterations: 1000) { try await sleep(for: .nanoseconds(1)) }
   Measure.Async(iterations: 1000) { try await sleep(for: .microseconds(1)) }
   Measure.Async(iterations: 1000) { try await sleep(for: .milliseconds(1)) }
   Measure.Async(iterations: 1) { try await sleep(for: .seconds(1)) }
  }
 }
}
