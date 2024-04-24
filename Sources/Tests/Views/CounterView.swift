@_spi(ModuleReflection) import Acrylic
#if os(WASI) || canImport(SwiftUI)
#if os(WASI)
import TokamakDOM
#else
import SwiftUI
#endif

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
final class Counter: ObservableModule {
 static var shared = Counter()
 var count: Int = .zero
 @Published
 var delay: Double = .zero
 var void: some Module {
  if delay > .zero {
   notify("sleeping for \(delay) seconds …", for: .note)
  }

  Sleep.Async(for: .seconds(delay))

  switch count {
  case .zero: Print(0)
  case 1...: Map(1 ... count) { Print($0) }
  case ...(-1): Map(count ... 0) { Print(-$0) }
  default: ()
  }
 }

 var task: Task<(), Error>?
 
 @MainActor
 func callAsFunction(_ amount: Int) {
   state { $0.count += amount }
  callContext()
  Task { @Reflection in
   print(String.newline + contextInfo().joined(separator: ", "))
  }
 }
}

#endif

extension Module {
 @Reflection(unsafe)
 func contextInfo(_ id: AnyHashable? = nil) -> [String] {
  let key = id ?? (
   !(ID.self is Never.Type) && !(ID.self is EmptyID.Type) &&
    String(describing: self.id).readableRemovingQuotes != "nil" ?
    AnyHashable(self.id) : AnyHashable(
     Swift._mangledTypeName(Self.self) ?? String(describing: Self.self)
    )
  )

  let states = Reflection.states
  let state = states[key].unsafelyUnwrapped
  let context = state.mainContext
  let cache = context.cache
  let contextInfo = "contexts: " + cache.count.description.readable
  let reflectionInfo = "reflections: " +
   states.count.description.readable
  let tasksInfo = "tasks: " +
   cache.values.map {
    $0.tasks.keyTasks.count + $0.tasks.queue.count
   }
   .reduce(into: 0, +=).description.readable
  let indexInfo = "indices: " + state.indices.count.description.readable

  let valuesInfo = "values: " + state.values.count.description.readable

  return [
   contextInfo,
   reflectionInfo,
   tasksInfo,
   indexInfo,
   valuesInfo
  ]
 }
}
