/*
 import Core
 extension CaseIterable
 where Self: RawRepresentable, RawValue: AdditiveArithmetic,
 AllCases.Index: ExpressibleAsStart {
 static func += (_ lhs: inout Self, rhs: RawValue) {
 lhs = Self(rawValue: lhs.rawValue + rhs) ?? allCases[.start]
 }

 static func -= (_ lhs: inout Self, rhs: RawValue) {
 lhs = Self(rawValue: lhs.rawValue - rhs) ?? allCases[allCases.endIndex]
 }
 }

 extension Array.Index: ExpressibleAsStart {
 public static let start: Self = .zero
 }

 public extension [(Int, ModuleContext)] {
 @discardableResult
 mutating func removeValue(forKey key: Int) -> (Int, ModuleContext)? {
 if let index = firstIndex(where: { $0.0 == key }) {
 return remove(at: index)
 }
 return nil
 }

 mutating func insert(_ value: ModuleContext, forKey key: Int, at offset: Int) {
 if let index = firstIndex(where: { $0.0 == key }) {
 remove(at: index)
 }
 insert((key, value), at: Swift.min(offset, endIndex))
 }

 subscript(_ key: Int) -> ModuleContext? {
 get { first(where: { $0.0 == key })?.1 }
 set {
 if let newValue {
 if let index = firstIndex(where: { $0.0 == key }) {
 self[index] = newValue
 } else {
 append((key, newValue))
 }
 } else {
 removeAll(where: { $0.0 == key })
 }
 }
 }
 }*/
