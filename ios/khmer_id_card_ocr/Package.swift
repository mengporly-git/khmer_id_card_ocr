// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "khmer_id_card_ocr",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        .library(name: "khmer-id-card-ocr", targets: ["khmer_id_card_ocr"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager.git", exact: "1.20.0")
    ],
    targets: [
        .binaryTarget(name: "libtesseract", path: "libtesseract.xcframework"),
        .target(
            name: "khmer_id_card_ocr",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                "libtesseract",
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
            ],
            linkerSettings: [
                .linkedLibrary("c++"),
                .linkedLibrary("z")
            ]
        )
    ]
)
