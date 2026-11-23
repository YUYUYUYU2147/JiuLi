import Charts
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject private var store: ArchiveStore
    @State private var isImporting = false
    @State private var isExporting = false
    @State private var exportDocument = ArchiveFileDocument(data: Data())
    @State private var poolFilter = "全部卡池"
    @State private var startDate = Calendar.current.date(byAdding: .year, value: -20, to: .now) ?? .distantPast
    @State private var endDate = Date.now

    private var pools: [String] {
        Array(Set(store.pulls.filter { $0.game == store.selectedGame }.map { poolKey(for: $0) })).filter { !$0.isEmpty }.sorted()
    }

    private var filteredPulls: [PullRecord] {
        store.visiblePulls.filter { record in
            let date = PullRecord.dateFormatter.date(from: record.time)
            let matchesPool = poolFilter == "全部卡池" || poolKey(for: record) == poolFilter
            let matchesDate = date.map { $0 >= startDate && $0 <= Calendar.current.date(byAdding: .day, value: 1, to: endDate)! } ?? true
            return matchesPool && matchesDate
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: Binding<GameID?>(
                get: { store.selectedGame },
                set: { if let game = $0 { store.selectedGame = game } }
            )) {
                Section("游戏") {
                    ForEach(GameID.allCases) { game in
                        Label {
                            Text(game.title)
                                .lineLimit(1)
                        } icon: {
                            Image(game.assetName)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 30, height: 30)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                        .tag(game)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("星愿档案")
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            VStack(spacing: 0) {
                gameHeader
                Picker("视图", selection: $store.selectedTab) {
                    ForEach(ArchiveTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 12)

                Group {
                    switch store.selectedTab {
                    case .records: recordsView
                    case .statistics: statisticsView
                    case .summaries: summariesView
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color(red: 0.055, green: 0.067, blue: 0.078))
            .navigationTitle(store.selectedGame.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        isImporting = true
                    } label: {
                        Label("导入", systemImage: "square.and.arrow.down")
                    }
                    .help("导入抽卡 JSON")

                    Button(action: beginExport) {
                        Label("导出", systemImage: "square.and.arrow.up")
                    }
                    .help("导出完整档案")
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let didAccess = url.startAccessingSecurityScopedResource()
                defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
                store.importArchive(data: try Data(contentsOf: url))
            } catch {
                store.errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $isExporting,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "星愿档案-完整备份"
        ) { result in
            if case .failure(let error) = result { store.errorMessage = error.localizedDescription }
        }
        .alert("提示", isPresented: noticePresented) {
            Button("好", role: .cancel) { store.notice = nil }
        } message: {
            Text(store.notice ?? "")
        }
        .alert("无法完成", isPresented: errorPresented) {
            Button("好", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var gameHeader: some View {
        HStack(spacing: 16) {
            Image(store.selectedGame.assetName)
                .resizable()
                .scaledToFill()
                .frame(width: 68, height: 68)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 5) {
                Text(store.selectedGame.title)
                    .font(.system(size: 24, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("抽卡档案")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 20)
            let gamePulls = store.pulls.filter { $0.game == store.selectedGame }
            metric(store.selectedGame == .bh3 ? "补给记录" : "抽数", value: "\(gamePulls.count)")
            if store.selectedGame == .bh3 {
                metric("补给类别", value: "\(Set(gamePulls.map(\.itemType).filter { !$0.isEmpty }).count)")
            } else {
                metric("五星", value: "\(gamePulls.filter { $0.rank >= 5 }.count)")
            }
            metric("账号", value: "\(store.uniqueUIDs)")
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(red: 0.085, green: 0.105, blue: 0.115))
    }

    private func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .trailing, spacing: 4) {
            Text(value).font(.system(size: 21, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
        .frame(minWidth: 66)
    }

    private var recordsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("搜索物品、UID 或卡池", text: $store.searchText)
                    .textFieldStyle(.plain)
                Menu {
                    Button("全部卡池") { poolFilter = "全部卡池" }
                    ForEach(pools, id: \.self) { pool in
                    Button(poolName(pool)) { poolFilter = pool }
                    }
                } label: {
                    Label(poolFilter == "全部卡池" ? "卡池" : poolName(poolFilter), systemImage: "line.3.horizontal.decrease")
                }
                .fixedSize()

                Menu {
                    DatePicker("开始日期", selection: $startDate, in: Date.distantPast...endDate, displayedComponents: .date)
                    DatePicker("结束日期", selection: $endDate, in: startDate..., displayedComponents: .date)
                    Button("重置日期") {
                        startDate = Calendar.current.date(byAdding: .year, value: -20, to: .now) ?? .distantPast
                        endDate = .now
                    }
                } label: {
                    Label("时间", systemImage: "calendar")
                }
                .fixedSize()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 8))
            .padding(.horizontal, 22)

            if filteredPulls.isEmpty {
                EmptyStateView(
                    title: store.pulls.contains(where: { $0.game == store.selectedGame }) ? "没有匹配记录" : "尚无抽卡记录",
                    symbol: "tray",
                    detail: store.pulls.contains(where: { $0.game == store.selectedGame }) ? "调整搜索词或筛选条件。" : "导入星愿档案备份或 UIGF JSON 开始查看。"
                )
            } else {
                HStack {
                    Text("\(filteredPulls.count) 条记录")
                    Spacer()
                    Text("按时间排序")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(filteredPulls) { record in
                            PullRow(record: record)
                            Divider().overlay(Color.white.opacity(0.04)).padding(.leading, 70)
                        }
                    }
                    .padding(.horizontal, 22)
                }
            }
        }
        .padding(.top, 8)
    }

    @ViewBuilder
    private var statisticsView: some View {
        let rows = store.pulls.filter { $0.game == store.selectedGame }
        if store.selectedGame == .bh3 {
            bh3Statistics(rows)
        } else {
            let distribution = (2...5).map { rank in
                RankCount(rank: rank, count: rows.filter { $0.rank == rank }.count)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 12) {
                        statisticBlock("总抽数", value: "\(rows.count)", symbol: "sparkles")
                        statisticBlock("五星", value: "\(rows.filter { $0.rank >= 5 }.count)", symbol: "star.fill")
                        statisticBlock("四星", value: "\(rows.filter { $0.rank == 4 }.count)", symbol: "star.leadinghalf.filled")
                    }

                    VStack(alignment: .leading, spacing: 16) {
                        Text("稀有度分布").font(.headline)
                        Chart(distribution) { value in
                            BarMark(x: .value("记录数", value.count), y: .value("稀有度", "\(value.rank) 星"))
                                .foregroundStyle(rankColor(value.rank))
                                .annotation(position: .trailing) { Text("\(value.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                        }
                        .frame(height: 190)
                        .chartXAxis { AxisMarks(position: .bottom) }
                    }
                    .padding(20)
                    .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
                }
                .padding(24)
            }
        }
    }

    private func bh3Statistics(_ rows: [PullRecord]) -> some View {
        let counts = Dictionary(grouping: rows, by: { $0.itemType.isEmpty ? "其他补给" : $0.itemType })
            .map { PoolCount(name: $0.key, count: $0.value.count) }
            .sorted { $0.count > $1.count }
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 12) {
                    statisticBlock("补给记录", value: "\(rows.count)", symbol: "sparkles")
                    statisticBlock("补给类别", value: "\(counts.count)", symbol: "square.grid.2x2")
                    statisticBlock("账号", value: "\(store.uniqueUIDs)", symbol: "person.crop.circle")
                }
                VStack(alignment: .leading, spacing: 16) {
                    Text("各类补给记录").font(.headline)
                    Chart(counts) { value in
                        BarMark(x: .value("记录数", value.count), y: .value("补给类型", value.name))
                            .foregroundStyle(Color(red: 0.88, green: 0.57, blue: 0.34))
                            .annotation(position: .trailing) { Text("\(value.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
                    }
                    .frame(height: max(150, CGFloat(counts.count) * 48))
                }
                .padding(20)
                .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(24)
        }
    }

    private var summariesView: some View {
        let summaries = store.visibleSummaries
        return Group {
            if summaries.isEmpty {
                EmptyStateView(title: "没有来源总览", symbol: "chart.bar.doc.horizontal", detail: "当前游戏的工坊或历史来源总览会显示在这里。")
            } else {
                List {
                    ForEach(summaries) { summary in
                        Section {
                            ForEach(summary.sections) { section in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Text(section.title).font(.headline)
                                        Spacer()
                                        Text("\(section.totalPulls) 抽 · \(section.rareCount) 个五星")
                                            .font(.subheadline).foregroundStyle(.secondary)
                                    }
                                    ForEach(section.items) { item in
                                        HStack {
                                            Image(systemName: "star.fill").foregroundStyle(rankColor(5))
                                            Text(item.name)
                                            Spacer()
                                            if item.pity > 0 { Text("\(item.pity) 抽").foregroundStyle(.secondary) }
                                            Text(item.time).foregroundStyle(.tertiary)
                                        }
                                        .font(.subheadline)
                                    }
                                }
                                .padding(.vertical, 5)
                            }
                        } header: {
                            HStack {
                                Text(summary.source)
                                Spacer()
                                Text("UID \(summary.uid)")
                            }
                        } footer: {
                            Text(summary.updated.isEmpty ? "" : "更新：\(summary.updated)")
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func statisticBlock(_ title: String, value: String, symbol: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(Color(red: 0.88, green: 0.57, blue: 0.34))
            Text(value).font(.system(size: 26, weight: .semibold, design: .rounded)).foregroundStyle(.white)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .leading)
        .padding(16)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
    }

    private var noticePresented: Binding<Bool> {
        Binding(get: { store.notice != nil }, set: { if !$0 { store.notice = nil } })
    }

    private var errorPresented: Binding<Bool> {
        Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })
    }

    private func beginExport() {
        do {
            exportDocument = ArchiveFileDocument(data: try store.exportData())
            isExporting = true
        } catch {
            store.errorMessage = error.localizedDescription
        }
    }

    private func poolKey(for record: PullRecord) -> String {
        store.selectedGame == .bh3 ? record.itemType : record.pool
    }

    private func poolName(_ key: String) -> String {
        if store.selectedGame == .bh3 { return key.isEmpty ? "其他补给" : key }
        return store.selectedGame.poolName(key)
    }
}

private struct PullRow: View {
    let record: PullRecord

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 3)
                .fill(rankColor(record.rank))
                .frame(width: 5, height: 42)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(record.name)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.white)
                        .lineLimit(record.game == .bh3 ? 3 : 1)
                        .fixedSize(horizontal: false, vertical: true)
                    if record.rank >= 5 {
                        Text("\(record.rank)★")
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(rankColor(record.rank))
                    }
                    if record.isUp == true {
                        Text("UP").font(.caption2.bold()).foregroundStyle(Color(red: 0.3, green: 0.8, blue: 0.62))
                    }
                }
                HStack(spacing: 10) {
                    Text(record.game == .bh3 ? (record.itemType.isEmpty ? "其他补给" : record.itemType) : record.game.poolName(record.pool))
                    if record.game != .bh3 && !record.itemType.isEmpty { Text(record.itemType) }
                    Text("UID \(record.uid)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Text(record.time)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

private struct EmptyStateView: View {
    let title: String
    let symbol: String
    let detail: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(.secondary)
            Text(title).font(.headline).foregroundStyle(.white)
            Text(detail).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RankCount: Identifiable {
    let rank: Int
    let count: Int
    var id: Int { rank }
}

private struct PoolCount: Identifiable {
    let name: String
    let count: Int
    var id: String { name }
}

private extension PullRecord {
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()
}

private func rankColor(_ rank: Int) -> Color {
    switch rank {
    case 5...: return Color(red: 0.96, green: 0.69, blue: 0.31)
    case 4: return Color(red: 0.78, green: 0.54, blue: 0.91)
    case 3: return Color(red: 0.37, green: 0.63, blue: 0.91)
    default: return Color(red: 0.46, green: 0.69, blue: 0.60)
    }
}
