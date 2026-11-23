import Foundation
import SwiftUI

enum GameID: String, CaseIterable, Identifiable, Hashable {
    case genshin, starRail, zzz, waves, nte, bh3

    var id: String { rawValue }

    var title: String {
        switch self {
        case .genshin: return "原神"
        case .starRail: return "崩坏：星穹铁道"
        case .zzz: return "绝区零"
        case .waves: return "鸣潮"
        case .nte: return "异环"
        case .bh3: return "崩坏3"
        }
    }

    var shortTitle: String {
        switch self {
        case .starRail: return "星铁"
        case .genshin: return "原神"
        case .zzz: return "绝区零"
        case .waves: return "鸣潮"
        case .nte: return "异环"
        case .bh3: return "崩坏3"
        }
    }

    var assetName: String {
        switch self {
        case .genshin: return "GameGenshin"
        case .starRail: return "GameStarRail"
        case .zzz: return "GameZZZ"
        case .waves: return "GameWaves"
        case .nte: return "GameNTE"
        case .bh3: return "GameBH3"
        }
    }

    var archiveKeys: [String] {
        switch self {
        case .genshin: return ["hk4e", "hk4e_ugc"]
        case .starRail: return ["hkrpg"]
        case .zzz: return ["nap"]
        case .waves: return ["wuwa"]
        case .nte: return ["nte"]
        case .bh3: return ["bh3"]
        }
    }

    static func game(forArchiveKey key: String) -> GameID? {
        allCases.first { $0.archiveKeys.contains(key) }
    }

    func poolName(_ key: String) -> String {
        let names: [String: String]
        switch self {
        case .genshin:
            names = ["301": "角色活动", "302": "武器活动", "500": "集录祈愿", "200": "常驻祈愿", "100": "新手祈愿", "2000": "活动祈愿", "1000": "常驻祈愿"]
        case .starRail:
            names = ["11": "角色跃迁", "12": "光锥跃迁", "21": "角色跃迁", "22": "光锥跃迁", "1": "常驻跃迁", "2": "新手跃迁"]
        case .zzz:
            names = ["2001": "独家频段", "3001": "音擎频段", "12001": "独家频段（重映）", "13001": "音擎频段（重映）", "1001": "常驻频段", "5001": "邦布频段", "1": "独家频段", "2": "音擎频段", "3": "常驻频段", "5": "邦布频段"]
        case .waves:
            names = ["1": "角色活动唤取", "2": "武器活动唤取", "3": "角色常驻唤取", "4": "武器常驻唤取", "5": "新手唤取"]
        case .nte:
            names = ["limited": "限定卡池", "standard": "常驻卡池", "fork": "弧盘池"]
        case .bh3:
            names = ["supply": "补给"]
        }
        return names[key] ?? "卡池 \(key)"
    }
}

struct PullRecord: Identifiable, Hashable {
    let game: GameID
    let uid: String
    let idValue: String
    let pool: String
    let name: String
    let itemType: String
    let rank: Int
    let time: String
    let isUp: Bool?

    var id: String { "\(game.rawValue)|\(uid)|\(pool)|\(idValue)" }

    init?(game: GameID, row: [String: Any]) {
        guard let rawID = row["id"], !(rawID is NSNull),
              let itemName = row["item_name"] as? String ?? row["name"] as? String,
              let time = row["time"] as? String else { return nil }

        self.game = game
        uid = Self.string(row["uid"])
        idValue = Self.string(rawID)
        pool = Self.string(row["uigf_gacha_type"] ?? row["gacha_type"] ?? row["op_gacha_type"])
        name = itemName
        itemType = row["item_type"] as? String ?? ""

        let rawRank = Int(Self.string(row["rank_type"])) ?? 0
        if game == .zzz && (2...4).contains(rawRank) {
            rank = rawRank + 1
        } else {
            rank = rawRank
        }
        self.time = time
        isUp = row["is_up"] as? Bool ?? row["isUp"] as? Bool ?? row["is_up_item"] as? Bool
    }

    private static func string(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        if let string = value as? String { return string }
        return String(describing: value)
    }
}

struct SummaryItem: Identifiable {
    let name: String
    let pity: Int
    let time: String
    var id: String { "\(name)|\(time)|\(pity)" }
}

struct SummarySection: Identifiable {
    let title: String
    let totalPulls: Int
    let rareCount: Int
    let items: [SummaryItem]
    var id: String { title }
}

struct SourceSummary: Identifiable {
    let game: GameID
    let uid: String
    let source: String
    let updated: String
    let sections: [SummarySection]
    var id: String { "\(game.rawValue)|\(uid)|\(source)" }

    init?(json: [String: Any]) {
        guard let gameKey = json["game"] as? String,
              let game = GameID(rawValue: gameKey) ?? Self.gameFromKey(gameKey) else { return nil }
        self.game = game
        uid = json["uid"] as? String ?? ""
        source = json["source"] as? String ?? json["name"] as? String ?? "记录总览"
        updated = Self.dateString(json["updated"])
        let rawSections = json["sections"] as? [[String: Any]] ?? []
        sections = rawSections.map { section in
            let rawItems = section["items"] as? [[String: Any]] ?? []
            let items = rawItems.map { item in
                SummaryItem(
                    name: item["item_name"] as? String ?? item["name"] as? String ?? "未知物品",
                    pity: Int(Self.string(item["pity"])) ?? 0,
                    time: Self.itemTime(item)
                )
            }
            return SummarySection(
                title: section["banner_name"] as? String ?? section["name"] as? String ?? "卡池",
                totalPulls: Int(Self.string(section["total_pull_count"])) ?? Int(Self.string(section["total"] )) ?? 0,
                rareCount: Int(Self.string(section["ssr_count"])) ?? Int(Self.string(section["rare_count"])) ?? items.count,
                items: items
            )
        }
    }

    private static func gameFromKey(_ value: String) -> GameID? {
        switch value {
        case "hk4e", "hk4e_ugc", "gs", "genshin": return .genshin
        case "hkrpg", "sr", "starRail": return .starRail
        case "nap", "zzz": return .zzz
        case "wuwa", "ww", "waves": return .waves
        case "nte": return .nte
        case "bh3": return .bh3
        default: return nil
        }
    }

    private static func string(_ value: Any?) -> String {
        guard let value, !(value is NSNull) else { return "" }
        return String(describing: value)
    }

    private static func itemTime(_ item: [String: Any]) -> String {
        if let value = item["pull_time"] as? String ?? item["time"] as? String { return value }
        let seconds = Double(string(item["pull_time_ts"] ?? item["time_ts"])) ?? 0
        guard seconds > 0 else { return "" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date(timeIntervalSince1970: seconds))
    }

    private static func dateString(_ value: Any?) -> String {
        guard let raw = value, !(raw is NSNull) else { return "" }
        if let string = raw as? String, let seconds = Double(string) {
            return dateFormatter.string(from: Date(timeIntervalSince1970: seconds))
        }
        if let number = raw as? NSNumber {
            return dateFormatter.string(from: Date(timeIntervalSince1970: number.doubleValue))
        }
        return String(describing: raw)
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter
    }()
}
