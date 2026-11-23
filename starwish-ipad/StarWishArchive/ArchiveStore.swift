import Foundation
import Combine
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ArchiveStore: ObservableObject {
    @Published var selectedGame: GameID = .genshin
    @Published var selectedTab: ArchiveTab = .records
    @Published var searchText = ""
    @Published private(set) var pulls: [PullRecord] = []
    @Published private(set) var summaries: [SourceSummary] = []
    @Published var notice: String?
    @Published var errorMessage: String?

    private var root: [String: Any] = ArchiveStore.emptyArchive()

    init() {
        let url = Self.archiveURL
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data),
              let json = object as? [String: Any] else { return }
        root = json
        rebuildModels()
    }

    var visiblePulls: [PullRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        return pulls
            .filter { $0.game == selectedGame }
            .filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) || $0.uid.localizedCaseInsensitiveContains(query) || $0.pool.localizedCaseInsensitiveContains(query) }
            .sorted { $0.time == $1.time ? $0.idValue > $1.idValue : $0.time > $1.time }
    }

    var visibleSummaries: [SourceSummary] {
        summaries.filter { $0.game == selectedGame }
    }

    var uniqueUIDs: Int {
        Set(pulls.filter { $0.game == selectedGame }.map(\.uid).filter { !$0.isEmpty }).count
    }

    func importArchive(data: Data) {
        let previousRoot = root
        do {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw ArchiveError.invalidFormat
            }
            var imported = 0
            var seen = Set(pulls.map(\.id))
            for key in GameID.allCases.flatMap(\.archiveKeys) {
                guard let rows = object[key] as? [[String: Any]],
                      let game = GameID.game(forArchiveKey: key) else { continue }
                var current = root[key] as? [[String: Any]] ?? []
                for row in rows {
                    guard let record = PullRecord(game: game, row: row), seen.insert(record.id).inserted else { continue }
                    current.append(row)
                    imported += 1
                }
                root[key] = current
            }

            let incomingSummaries = object["source_summaries"] as? [[String: Any]] ?? []
            var currentSummaries = root["source_summaries"] as? [[String: Any]] ?? []
            for summary in incomingSummaries {
                let key = [summary["game"], summary["uid"], summary["source"]].map { String(describing: $0 ?? "") }.joined(separator: "|")
                if let index = currentSummaries.firstIndex(where: {
                    [ $0["game"], $0["uid"], $0["source"] ]
                        .map { String(describing: $0 ?? "") }
                        .joined(separator: "|") == key
                }) {
                    currentSummaries[index] = summary
                } else {
                    currentSummaries.append(summary)
                }
            }
            if !incomingSummaries.isEmpty { root["source_summaries"] = currentSummaries }

            guard imported > 0 || !incomingSummaries.isEmpty else { throw ArchiveError.noRecords }
            rebuildModels()
            try persist()
            notice = "已导入 \(imported) 条抽卡记录和 \(incomingSummaries.count) 个来源总览"
            errorMessage = nil
        } catch {
            root = previousRoot
            rebuildModels()
            errorMessage = error.localizedDescription
        }
    }

    func exportData() throws -> Data {
        try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    private func rebuildModels() {
        var records: [PullRecord] = []
        for key in GameID.allCases.flatMap(\.archiveKeys) {
            guard let game = GameID.game(forArchiveKey: key),
                  let rows = root[key] as? [[String: Any]] else { continue }
            records.append(contentsOf: rows.compactMap { PullRecord(game: game, row: $0) })
        }
        pulls = records
        summaries = (root["source_summaries"] as? [[String: Any]] ?? []).compactMap(SourceSummary.init(json:))
    }

    private func persist() throws {
        let data = try exportData()
        try data.write(to: Self.archiveURL, options: .atomic)
    }

    private static var archiveURL: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("WishArchive.json")
    }

    private static func emptyArchive() -> [String: Any] {
        var archive: [String: Any] = [
            "info": [
                "export_app": "星愿档案 iPad",
                "export_app_version": "0.1.0",
                "version": "v4.2"
            ],
            "source_summaries": [[String: Any]]()
        ]
        for key in GameID.allCases.flatMap(\.archiveKeys) { archive[key] = [[String: Any]]() }
        return archive
    }
}

enum ArchiveTab: String, CaseIterable, Identifiable, Hashable {
    case records = "抽卡记录"
    case statistics = "统计"
    case summaries = "来源总览"
    var id: String { rawValue }
}

enum ArchiveError: LocalizedError {
    case invalidFormat
    case noRecords

    var errorDescription: String? {
        switch self {
        case .invalidFormat: return "无法读取此 JSON 文件。"
        case .noRecords: return "文件中没有可识别的抽卡记录或来源总览。"
        }
    }
}

struct ArchiveFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
