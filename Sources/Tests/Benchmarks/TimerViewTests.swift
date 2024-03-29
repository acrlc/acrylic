import Benchmarks

struct TestTimerView: Tests {
 let assert: KeyValuePairs<String, Duration> = [
  "0:00:45": .seconds(45),
  "0:01:00": .seconds(60),
  "0:03:55": .minutes(3) + .seconds(55),
  "0:07:00": .minutes(7),
  "1:00:00": .minutes(60),
  "1:01:00": .minutes(61),
  "1:00:01": .minutes(60) + .seconds(1),
  "1:13:46": .seconds(4426),
  "1:55:09": .hours(1) + .minutes(55) + .seconds(9),
  "4:00:00": .hours(4),
  "23:56:34": .hours(23) + .minutes(56) + .seconds(34),
  "23:59:49": .hours(23) + .minutes(59) + .seconds(49),
  "48:00:03": .days(2) + .seconds(3),
  "50:17:59": .hours(50) + .minutes(17) + .seconds(59),
  "95:59:02": .days(3) + .hours(23) + .minutes(59) + .seconds(2)
 ]

 var tests: some Testable {
  /// Test duration with the `formatted()` function
  #if os(macOS)
  Test("Duration.formatted()") {
   for (label, duration) in assert {
    Identity(label) == duration.formatted()
   }
  }
  #endif

  /// Test duration with the `timerView` property
  Test("Duration.timerView") {
   for (label, duration) in assert {
    Identity(label) == duration.timerView
   }
  }

  /// Compares when compiled on macOS or simply performs a speed benchmark
  Benchmarks("Format Duration") {
   let durations = assert.map(\.1)

   #if os(macOS)
   Measure("Duration.formatted()", iterations: 111) {
    for duration in durations {
     blackHole(duration.formatted())
    }
   }
   #endif
   Measure("Duration.timerView", iterations: 111) {
    for duration in durations {
     blackHole(duration.timerView)
    }
   }
  }
 }
}

struct TestLossLessStringDuration: Tests {
 let assert: KeyValuePairs<String, Duration> = [
  "1nanosecond": .nanoseconds(1),
  "1microsecond": .microseconds(1),
  "1millisecond": .milliseconds(1),
  "1second": .nanoseconds(1_000_000_000),
  "1second": .seconds(1),
  "1minute": .minutes(1),
  "1hour": .hours(1),
  "1day": .hours(24),
  "7days": .hours(24 * 7),
  "356days": .days(356)
 ]

 var tests: some Testable {
  get throws {
   /// Test ``LosslessStringConvertible`` conformance
   for (label, duration) in assert {
    try Identity(duration) == Duration(label).throwing()
   }
   Benchmarks {
    let labels = assert.map(\.0)
    Measure("Initialize Duration", iterations: 111) {
     for label in labels {
      try blackHole(Duration(label).throwing())
     }
    }
   }
  }
 }
}

struct TestDurationExtensions: Tests {
 var tests: some Testable {
  TestTimerView()
  TestLossLessStringDuration()
 }
}
