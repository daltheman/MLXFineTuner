import Foundation

class HuggingFaceService {
    private let session: URLSession = {
        let cfg = URLSessionConfiguration.default
        cfg.timeoutIntervalForRequest = 15
        return URLSession(configuration: cfg)
    }()

    // MARK: - Search

    func searchModels(query: String, mlxCommunityOnly: Bool = true) async throws -> [HFModelResult] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "full", value: "false"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
        ]
        if !query.isEmpty { items.append(URLQueryItem(name: "search", value: query)) }
        if mlxCommunityOnly {
            items.append(URLQueryItem(name: "author", value: "mlx-community"))
        } else {
            items.append(URLQueryItem(name: "filter", value: "mlx"))
        }
        return try await fetch([HFModelResult].self, path: "models", queryItems: items)
    }

    func searchDatasets(query: String) async throws -> [HFDatasetResult] {
        var items: [URLQueryItem] = [
            URLQueryItem(name: "limit", value: "40"),
            URLQueryItem(name: "full", value: "false"),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
        ]
        if !query.isEmpty { items.append(URLQueryItem(name: "search", value: query)) }
        return try await fetch([HFDatasetResult].self, path: "datasets", queryItems: items)
    }

    // MARK: - Download

    /// Downloads a dataset via huggingface_hub.snapshot_download (blocking — run on background thread).
    func downloadDataset(id: String, toPath: String, pythonPath: String, onLog: @escaping (String) -> Void) throws {
        let script = """
import sys
try:
    from huggingface_hub import snapshot_download
    path = snapshot_download(repo_id=sys.argv[1], repo_type='dataset', local_dir=sys.argv[2])
    print(f'SUCCESS: {path}')
except Exception as e:
    print(f'ERROR: {e}', file=sys.stderr)
    sys.exit(1)
"""
        let process = Process()
        let outPipe = Pipe()
        let errPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [pythonPath, "-c", script, id, toPath]
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.environment = enrichedEnv()

        for pipe in [outPipe, errPipe] {
            pipe.fileHandleForReading.readabilityHandler = { handle in
                guard let text = String(data: handle.availableData, encoding: .utf8),
                      !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else { return }
                onLog(text.trimmingCharacters(in: .whitespacesAndNewlines))
            }
        }

        try process.run()
        process.waitUntilExit()
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil

        guard process.terminationStatus == 0 else {
            throw NSError(
                domain: "HuggingFaceService",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: "Download failed (exit \(process.terminationStatus))"]
            )
        }
    }

    // MARK: - Helpers

    private func fetch<T: Decodable>(_ type: T.Type, path: String, queryItems: [URLQueryItem]) async throws -> T {
        var components = URLComponents(string: "https://huggingface.co/api/\(path)")!
        components.queryItems = queryItems
        let (data, response) = try await session.data(from: components.url!)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func enrichedEnv() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let extra = ["/usr/local/bin", "/opt/homebrew/bin", "/opt/homebrew/opt/python/bin"]
        env["PATH"] = (extra + [env["PATH"] ?? ""]).joined(separator: ":")
        return env
    }
}
