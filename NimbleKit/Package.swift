// swift-tools-version: 6.0
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "NimbleKit",
	platforms: [
		.iOS(.v16),
		.tvOS(.v16)
	],
	products: [
		.library(name: "NimbleExtensions", targets: ["NimbleExtensions"]),
		.library(name: "NimbleJSON", targets: ["NimbleJSON"]),
		.library(name: "NimbleViews", targets: ["NimbleViews"]),
	],
	dependencies: [
		// Same pin the project already resolves for zsign; NimbleExtensions is
		// the only place that may import it (see OpenSSLPackaging.swift).
		.package(url: "https://github.com/krzyzanowskim/OpenSSL", from: "3.3.3001")
	],
	targets: [
		.target(
			name: "NimbleViews",
			dependencies: ["NimbleExtensions"]
		),
		.target(
			name: "NimbleExtensions",
			dependencies: [
				.product(name: "OpenSSL", package: "OpenSSL")
			]
		),
		.target(name: "NimbleJSON",
			dependencies: []
		)
	]
)
