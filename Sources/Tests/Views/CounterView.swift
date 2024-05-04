@_spi(ModuleReflection) import Acrylic
#if os(WASI) || canImport(SwiftUI)
#if os(WASI)
import TokamakDOM
#else
import SwiftUI
#endif
import Time

@available(macOS 13, iOS 16, *)
struct CounterView: View {
 @ObservedAlias(Counter.self)
 var counter

 var delayOptions: [Double] { [0.0, 0.5, 1.0, 1.5, 2.0, 2.5, 3.0] }
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
      .frame(minWidth: 38)
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

@available(macOS 13, iOS 16, *)
// MARK: Counter Module
final class Counter: ObservableModule, @unchecked Sendable {
 static var shared = Counter()
 var count: Int = .zero
 var timer = Timer()
 @Published
 var delay: Double = .zero
 var void: some Module {
  Perform.Async {
   if delay > .zero {
    notify("sleeping for \(delay) seconds …", for: .note)
    try await sleep(for: .seconds(delay))
   }

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

   let endTime = timer.elapsed
   let updateInterval = endTime.seconds - delay

   print("~", Time(updateInterval))
  }
 }

 var task: Task<(), Error>?

 @MainActor
 func callAsFunction(_ amount: Int) {
  callState {
   $0.count += amount
   $0.timer.fire()
  }
  print(String.newline + contextInfo().joined(separator: ", "))
 }
}

#endif
