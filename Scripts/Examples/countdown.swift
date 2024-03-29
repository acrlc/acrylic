#!/usr/bin/env swift-shell
import Acrylic // ../..
import func Foundation.sleep

struct Countdown: Module {
 var void: some Module {
  Map((1 ... 3).map { $0 }.reversed()) { int in
   Perform {
    print(int, "…")
    sleep(1)
   }
  }
  Perform { print("finished!") }
 }
}

try await Countdown().callAsFunction()
