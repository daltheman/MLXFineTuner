import Foundation

struct HFModelResult: Identifiable, Decodable {
    let id: String
    let downloads: Int?
    let likes: Int?
    let tags: [String]?
    let pipelineTag: String?

    enum CodingKeys: String, CodingKey {
        case id, downloads, likes, tags
        case pipelineTag = "pipeline_tag"
    }

    var formattedDownloads: String { format(downloads) }
    var formattedLikes: String { format(likes) }

    private func format(_ n: Int?) -> String {
        guard let n else { return "—" }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }
}

struct HFDatasetResult: Identifiable, Decodable {
    let id: String
    let downloads: Int?
    let likes: Int?
    let tags: [String]?

    var formattedDownloads: String {
        guard let n = downloads else { return "—" }
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fk", Double(n) / 1_000) }
        return "\(n)"
    }
}
