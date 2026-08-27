import Foundation
import Testing

/// Easy Write reads the pasteboard and never writes it, except in the single code path behind the
/// popover's Copy button. That promise is worth stating because it is countable rather than
/// something a reviewer has to remember, and this test is the count.
@Test("given the app sources, when every pasteboard write is located, then they all sit in one function")
func onlyOneFunctionWritesThePasteboard() throws {
    // The pasteboard-writing surface of NSPasteboard is a closed list, so scanning for it is exact.
    let writingAPIs = ["clearContents", "writeObjects", "setString", "setData",
                       "setPropertyList", "declareTypes", "prepareForNewContents"]
    var owners: Set<String> = []

    for file in try swiftFiles(in: sourcesDirectory) {
        let lines = try String(contentsOf: file, encoding: .utf8).components(separatedBy: .newlines)
        var enclosingFunction = "(file scope)"
        for line in lines {
            if let name = declaredFunctionName(in: line) { enclosingFunction = name }
            if writingAPIs.contains(where: { line.contains(".\($0)(") }) {
                owners.insert("\(file.lastPathComponent):\(enclosingFunction)")
            }
        }
    }

    #expect(owners == ["Clipboard.swift:write"],
            "exactly one function may write the pasteboard, found: \(owners.sorted())")
}

/// The name declared by a `func` line, or nil for anything else — including a line that merely
/// mentions one, so a doc comment cannot be mistaken for a declaration.
private func declaredFunctionName(in line: String) -> String? {
    let tokens = line.split(separator: " ").map(String.init)
    guard let index = tokens.firstIndex(of: "func"), index + 1 < tokens.count else { return nil }
    let modifiers: Set<String> = ["private", "fileprivate", "internal", "public", "open", "static",
                                  "class", "final", "override", "nonisolated", "mutating",
                                  "@objc", "@MainActor", "@discardableResult"]
    guard tokens[..<index].allSatisfy(modifiers.contains) else { return nil }
    let name = tokens[index + 1].prefix { $0.isLetter || $0.isNumber || $0 == "_" }
    return name.isEmpty ? nil : String(name)
}

private var sourcesDirectory: URL {
    URL(fileURLWithPath: #filePath)     // Tests/EasyWriteCoreTests/PasteboardWriteGuardTests.swift
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()    // repository root
        .appendingPathComponent("Sources")
}

private func swiftFiles(in directory: URL) throws -> [URL] {
    let paths = try FileManager.default.subpathsOfDirectory(atPath: directory.path)
    return paths.filter { $0.hasSuffix(".swift") }.map(directory.appendingPathComponent)
}
