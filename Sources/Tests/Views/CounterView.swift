@_spi(ModuleReflection) import Acrylic
#if os(WASI) || canImport(SwiftUI)
#if os(WASI)
import TokamakCore
#else
import SwiftUI
#endif
import Time

@available(macOS 13, iOS 16, *)
struct CounterView: View {
 @ObservedAlias(Counter.self)
 var counter

 var delayOptions: [Time] { [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0] }
 func switchDelay() {
  guard let index = delayOptions.firstIndex(of: counter.delay)
  else {
   fatalError()
  }
  let nextIndex = delayOptions.index(after: index)
  counter.delay = delayOptions[
   nextIndex < delayOptions.endIndex ? nextIndex : delayOptions.startIndex
  ]
 }

 var body: some View {
  VStack(alignment: .center) {
   HStack {
    Button(
     action: {
      counter(-1)
     },
     label: {
      Text("minus")
       .foregroundStyle(.secondary)
       .frame(minWidth: 38)
      #if !os(WASI)
       .contentShape(Rectangle())
       .allowsHitTesting(true)
      #endif
     }
    )

    Divider()
    Button(
     action: {
      counter(1)
     },
     label: {
      Text("plus")
       .frame(minWidth: 38)
      #if !os(WASI)
       .contentShape(Rectangle())
       .allowsHitTesting(true)
      #endif
     }
    )
   }
   .buttonStyle(.plain)
   .frame(height: 16)
   .padding(.horizontal)

   Text(counter.count.description)
    .font(.title)
    .opacity(0.95)
    .padding(.bottom, 1)

   HStack {
    let label: String = if counter.delay == .zero {
     "zero"
    } else {
     counter.delay.description
    }
    Text("sleep")
     .frame(minWidth: 38)
    Divider()
    Button(action: switchDelay) {
     Text(label)
      .frame(width: 38)
      .minimumScaleFactor(0.88)
     #if !os(WASI)
      .contentShape(Rectangle())
      .allowsHitTesting(true)
     #endif
    }
    .buttonStyle(.plain)
    .foregroundStyle(.secondary)
   }
   .frame(height: 16)
  }
  .frame(width: 128)
  .padding([.bottom, .horizontal])
 }
}

// MARK: Counter Module
@available(macOS 13, iOS 16, *)
final class Counter: ObservableModule, @unchecked Sendable {
 static var shared = Counter()
 var count: Int = .zero
 var updateTimer = Timer()
 @Published
 var delay: Time = .zero

 var void: some Module {
  Perform.Async {
   let time = updateTimer.elapsed

   await print(String.newline + contextInfo().joined(separator: ", "))

   if delay > .zero {
    notify("sleeping for \(delay) …", for: .note)
    try await sleep(for: delay.duration)
   }

   print("~" + time.description, "update")

   switch count {
   case .zero: print(0)
   case 1...:
    for int in 1 ... count {
     print(int)
    }
   case ...(-1):
    for int in count ... 0 {
     print(-int)
    }
   default: break
   }
  }

  /* TODO: Enable auto-capturing where possible and create an update method for
   bounded modules.
   
   let time = updateTimer.elapsed

   await Print(String.newline + contextInfo().joined(separator: ", "))

   if delay > .zero {
    Perform.Async { notify("sleeping for \(delay) …", for: .note) }
    Sleep.Async(for: delay.duration)
   }

   Print("~" + time.description, "update")

   switch count {
   case .zero: Print(0)
   case 1...:
    for int in 1 ... count {
     Print(int)
    }
   case ...(-1):
    for int in count ... 0 {
     Print(-int)
    }
   default: fatalError()
   }
    */
 }

 @MainActor
 func callAsFunction(_ amount: Int) {
  callState {
   count += amount
  }
  // an async update occurs immediately after call action
  updateTimer.fire()
 }
}
#endif
