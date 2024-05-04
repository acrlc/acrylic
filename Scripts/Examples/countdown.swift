#!/usr/bin/env swift-shell
import ModuleFunctions // ../..
import Foundation

@main
struct Countdown: MainFunction {
 @Context
 var offset: Int = .zero

 var void: some Module {
  Map((1 ... 3).map { $0 }.reversed()) { int in
   Perform {
    print(int, "…")
    sleep(1)
   }
  }
  
  Print(0)
  Sleep(for: 1e9)
  
  Repeat {
   if offset < 3 {
    print(offset + 1, "…")
    sleep(1)
    
    offset += 1
    return true
   } else {
    return false
   }
  }
  
  Print("finished!")
 }
}
