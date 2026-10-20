import Foundation
enum Secret {
    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lense", isDirectory: true).appendingPathComponent(".env")
    }
    static func read(from url: URL = fileURL) -> String {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text.components(separatedBy: .newlines).first(where: { $0.hasPrefix("OPENAI_API_KEY=") })
            .map { String($0.dropFirst("OPENAI_API_KEY=".count)) } ?? ""
    }
    static func save(_ value: String, to url: URL = fileURL) throws {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, !key.contains(where: { $0.isWhitespace || $0.isNewline }) else {
            throw NSError(domain: "Lense", code: 7, userInfo: [NSLocalizedDescriptionKey: "请输入完整的单行密钥。"])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        let data = Data("OPENAI_API_KEY=\(key)\n".utf8)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
let answerModel = "gpt-6-astra"
