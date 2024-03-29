// swift-tools-version:5.9
import PackageDescription

let useLibraryEvolution = false
let lint = false

let package = Package(
 name: "Acrylic",
 platforms: [.macOS(.v13), .iOS(.v16)],
 products: [
  .library(name: "Acrylic", targets: ["Acrylic"]),
  .library(name: "ModuleFunctions", targets: ["ModuleFunctions"]),
  .library(name: "Tests", targets: ["Tests"]),
  .executable(name: "acrylicTests", targets: ["AcrylicTests"])
 ],
 dependencies: [
  .package(url: "https://github.com/acrlc/Core.git", branch: "main"),
  .package(
   url: "https://github.com/philipturner/swift-reflection-mirror.git",
   branch: "main"
  ),
  // for Tests library
  .package(url: "https://github.com/acrlc/Time.git", branch: "main"),
  .package(url: "https://github.com/acrlc/Shell.git", branch: "main"),
  // for AcrylicTests binary
  .package(url: "https://github.com/acrlc/Configuration.git", branch: "main"),
  .package(url: "https://github.com/acrlc/Benchmarks.git", branch: "main")
 ],
 targets: [
  .target(
   name: "Acrylic",
   dependencies: [
    "Core",
    .product(name: "Extensions", package: "core"),
    .product(name: "ReflectionMirror", package: "swift-reflection-mirror")
   ],
   path: "Sources/Framework"
  ),
  .target(
   name: "ModuleFunctions", dependencies: ["Acrylic"],
   path: "Modules/Functions"
  ),
  .target(
   name: "Tests", dependencies: [
    "Time",
    "Shell",
    "Acrylic",
    "ModuleFunctions"
   ],
   path: "Modules/Tests"
  ),
  .executableTarget(
   name: "AcrylicTests",
   dependencies: ["Tests", "Benchmarks", "Configuration"],
   path: "Sources/Tests"
  ),
  .testTarget(name: "ModuleTests", dependencies: ["Acrylic"]),
  .testTarget(
   name: "ReflectionTests", dependencies: ["Acrylic"]
  ),
  .testTarget(
   name: "TestsTest",
   dependencies: ["Tests", "Benchmarks"]
  )
 ]
)

if useLibraryEvolution {
 for target in package.targets {
  if target.swiftSettings == nil {
   target.swiftSettings = []
  }
  target.swiftSettings? += [
   .unsafeFlags(["-enable-library-evolution"])
  ]
 }
}

#if arch(wasm32)
package.dependencies.append(
 .package(url: "https://github.com/acrlc/tokamak.git", branch: "main")
)
for target in package.targets {
 if target.name == "AcrylicTests" || target.name == "Acrylic" {
  target.dependencies += [
   .product(
    name: "TokamakShim",
    package: "Tokamak", condition: .when(platforms: [.wasi])
   )
  ]
  break
 }
}
#endif

if lint {
 package.dependencies.append(
  .package(url: "https://github.com/realm/swiftlint.git", branch: "0.54.0")
 )

 for target in package.targets {
  target.plugins = [
   .plugin(name: "SwiftLintPlugin", package: "swiftlint")
  ]
 }
}

/**
  # TODO: enable strict concurrency
 **/
/*
 for target in package.targets {
  var settings = target.swiftSettings ?? []
  settings.append(.enableExperimentalFeature("StrictConcurrency"))
  target.swiftSettings = settings
 }
 */
