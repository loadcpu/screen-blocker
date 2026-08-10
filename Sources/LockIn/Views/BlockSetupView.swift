import SwiftUI
import AppKit
import TimerInputSupport

private let blockSetupAccentBlue = Color(nsColor: .controlAccentColor)
private let timerFieldWidth: CGFloat = 126
private let timerFieldHeight: CGFloat = 172
private let timerSeparatorWidth: CGFloat = 28
private let timerSelectionCornerRadius: CGFloat = 16
private let timerSelectionHeight: CGFloat = 122
private let presetCardSize = CGSize(width: 158, height: 186)
private let presetGridSpacing: CGFloat = 16
private let presetGridWidth: CGFloat = 506
private let presetGridHeight: CGFloat = 388
private let presetCardCornerRadius: CGFloat = 16
private enum TimerField: Hashable {
    case hours
    case minutes
    case seconds
}

struct BlockSetupView: View {
    let onStart: (_ minutes: Int, _ apps: [String], _ websites: [String]) -> Void
    let onCancel: () -> Void

    @ObservedObject private var service = BlockerService.shared
    @State private var selectedMinutes = 60
    @State private var customText = ""
    @State private var hourInput = "01"
    @State private var minuteInput = "00"
    @State private var secondInput = "00"
    @State private var items: [BlockItem] = []
    @State private var checked: Set<String> = []
    @State private var isLoadingItems = true
    @State private var focusedTimeField: TimerField?
    @State private var hasInitializedSelection = false
    @State private var manageSection: ManageSection = .apps
    @State private var appSearch = ""
    @State private var websiteSearch = ""
    @State private var websiteError = ""

    private enum SetupStep: String, CaseIterable {
        case list = "List"
        case timer = "Timer"
    }
    private enum ManageSection: String, CaseIterable {
        case apps = "Apps"
        case websites = "Websites"
        case limits = "Limits"
    }
    @State private var step: SetupStep = .list
    @State private var hoveredStep: SetupStep?
    @State private var hoveredManageSection: ManageSection?

    init(
        onStart: @escaping (_ minutes: Int, _ apps: [String], _ websites: [String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onStart = onStart
        self.onCancel = onCancel

        let seededItems = Self.initialConfigItems(from: BlockerService.shared.config)
        _items = State(initialValue: seededItems)
        _checked = State(initialValue: Set(seededItems.map(\.id)))
        _hasInitializedSelection = State(initialValue: !seededItems.isEmpty)
    }

    private var timerPresetOptions: [Int] {
        Self.normalizedTimerPresets(service.config.timerPresets)
    }

    private var canDeleteSelectedPreset: Bool {
        timerPresetOptions.contains(selectedMinutes) && !defaultTimerPresets.contains(selectedMinutes)
    }

    private var isCustomSelected: Bool {
        !timerPresetOptions.contains(selectedMinutes)
    }

    private var hoursText: Binding<String> {
        Binding(
            get: { hourInput },
            set: { updateSelectedDuration(hours: $0, minutes: minuteInput, seconds: secondInput) }
        )
    }

    private var minutesText: Binding<String> {
        Binding(
            get: { minuteInput },
            set: { updateSelectedDuration(hours: hourInput, minutes: $0, seconds: secondInput) }
        )
    }

    private var secondsText: Binding<String> {
        Binding(
            get: { secondInput },
            set: { updateSelectedDuration(hours: hourInput, minutes: minuteInput, seconds: $0) }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            content
            actionBar
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea(edges: .top)
        .onAppear {
            syncTimeFieldsFromSelection()
            loadItems()
        }
    }

    private var topBar: some View {
        ZStack {
            HStack {
                Spacer()
                    .frame(width: 196)
                Spacer()
            }

            HStack(spacing: 0) {
                ForEach(SetupStep.allCases, id: \.self) { current in
                    Button {
                        guard current != .timer || checkedTotal > 0 else { return }
                        step = current
                        if current == .list {
                            focusedTimeField = nil
                        }
                    } label: {
                        Text(current.rawValue)
                            .font(.body.weight(.semibold))
                            .foregroundColor(tabForeground(for: current))
                            .frame(width: 104, height: 34)
                            .background(tabBackground(for: current))
                    }
                    .buttonStyle(.plain)
                    .disabled(current == .timer && checkedTotal == 0)
                    .onHover { isHovering in
                        hoveredStep = isHovering ? current : (hoveredStep == current ? nil : hoveredStep)
                    }

                    if current != SetupStep.allCases.last {
                        Divider()
                            .frame(height: 18)
                    }
                }
            }
            .background(Color.white.opacity(0.08))
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
        }
        .padding(.horizontal, 20)
        .padding(.top, 8)
        .padding(.bottom, 12)
        .appWindowSurface()
    }

    private var content: some View {
        Group {
            switch step {
            case .list:
                itemList
            case .timer:
                timerStep
            }
        }
    }

    // MARK: - Items list

    private var itemList: some View {
        ScrollView {
            VStack(spacing: 18) {
                manageSectionCard
            }
            .padding(.vertical, 12)
        }
        .frame(maxHeight: .infinity)
    }

    private var emptySelectionState: some View {
        VStack(spacing: 10) {
            Image(systemName: "checklist")
                .font(.system(size: 32))
                .foregroundColor(.secondary.opacity(0.4))
            Text("No apps or websites selected yet")
                .font(.body)
                .foregroundColor(.secondary)
            Text("Add what you want to block below, then continue to the timer.")
                .font(.footnote)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 20)
    }

    private var timerStep: some View {
        VStack(spacing: 34) {
            VStack(spacing: -6) {
                HStack(alignment: .center, spacing: 0) {
                    timeLabel("hr")
                    timeLabelSeparator
                    timeLabel("min")
                    timeLabelSeparator
                    timeLabel("sec")
                }

                HStack(alignment: .center, spacing: 0) {
                    timeField(hoursText, field: .hours)
                    timeSeparator
                    timeField(minutesText, field: .minutes)
                    timeSeparator
                    timeField(secondsText, field: .seconds)
                }
            }

            VStack(spacing: 16) {
                Text("Recent")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(.white.opacity(0.96))
                    .frame(width: presetGridWidth, alignment: .leading)

                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.fixed(presetCardSize.width), spacing: presetGridSpacing), count: 3),
                        spacing: presetGridSpacing
                    ) {
                        ForEach(timerPresetOptions, id: \.self) { mins in
                            presetCard(for: mins)
                        }
                    }
                    .padding(1)
                    .padding(.bottom, 4)
                }
                .frame(width: presetGridWidth, height: presetGridHeight)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 52)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private func sectionHeader(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.body.weight(.semibold))
                .foregroundColor(.secondary)
                .tracking(0.5)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 4)
    }

    private var manageSectionCard: some View {
        VStack(spacing: 0) {
            sectionHeader(manageSection == .limits ? "LIMITS" : "BLOCK LIST")
            if manageSection != .limits {
                selectionSummary
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
                    .padding(.bottom, 2)
            }
            manageSectionPicker
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 14)

            Group {
                switch manageSection {
                case .apps:
                    appsManager
                case .websites:
                    websitesManager
                case .limits:
                    limitsManager
                }
            }
        }
    }

    private var selectionSummary: some View {
        HStack(spacing: 10) {
            Text("\(checkedTotal) selected")
                .font(.footnote.weight(.semibold))
                .foregroundColor(.primary)

            Text("\(checkedApps.count) app\(checkedApps.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundColor(.secondary)

            Text("\(checkedSites.count) website\(checkedSites.count == 1 ? "" : "s")")
                .font(.footnote)
                .foregroundColor(.secondary)

            Spacer()
        }
    }

    private var manageSectionPicker: some View {
        HStack(spacing: 0) {
            ForEach(ManageSection.allCases, id: \.self) { section in
                Button {
                    manageSection = section
                } label: {
                    Text(section.rawValue)
                        .font(.body.weight(.semibold))
                        .foregroundColor(manageSectionForeground(for: section))
                        .frame(maxWidth: .infinity)
                        .frame(height: 34)
                        .background(manageSectionBackground(for: section))
                }
                .buttonStyle(.plain)
                .onHover { isHovering in
                    hoveredManageSection = isHovering ? section : (hoveredManageSection == section ? nil : hoveredManageSection)
                }

                if section != ManageSection.allCases.last {
                    Divider()
                        .frame(height: 18)
                }
            }
        }
        .background(Color.white.opacity(0.08))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var appsManager: some View {
        let displayedApps = libraryAppItems

        return VStack(spacing: 12) {
            librarySearchField(placeholder: "Search apps…", text: $appSearch)

            if displayedApps.isEmpty {
                HStack {
                    Text("No apps match your search")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
                .appCard(cornerRadius: 14)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedApps.enumerated()), id: \.element.id) { index, item in
                        itemRow(item)
                        if index < displayedApps.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .appCard(cornerRadius: 14)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var websitesManager: some View {
        let displayedSites = libraryWebsiteItems
        let canAddSearchAsWebsite = canAddWebsite(from: websiteSearch)

        return VStack(spacing: 12) {
            librarySearchField(
                placeholder: "Search websites…",
                text: $websiteSearch,
                onSubmit: addWebsiteFromSearch
            )

            if displayedSites.isEmpty {
                if canAddSearchAsWebsite {
                    Button {
                        addWebsiteFromSearch()
                    } label: {
                        HStack {
                            Text("Add \(normalizedWebsiteCandidate ?? websiteSearch)")
                                .font(.footnote.weight(.semibold))
                                .foregroundColor(.primary)
                            Spacer()
                            Image(systemName: "plus.circle.fill")
                                .foregroundColor(blockSetupAccentBlue)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 14)
                        .appCard(cornerRadius: 14)
                    }
                    .buttonStyle(.plain)
                } else {
                    HStack {
                        Text(websiteSearch.isEmpty ? "No websites added yet" : "No websites match your search")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                    .appCard(cornerRadius: 14)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedSites.enumerated()), id: \.element.id) { index, item in
                        websiteLibraryRow(item)
                        if index < displayedSites.count - 1 {
                            Divider().padding(.leading, 52)
                        }
                    }
                }
                .appCard(cornerRadius: 14)
            }

            if !websiteError.isEmpty {
                HStack {
                    Text(websiteError)
                        .font(.footnote)
                        .foregroundColor(.red)
                    Spacer()
                }
            }

        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func websiteLibraryRow(_ item: BlockItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: selectionBinding(for: item))
                .labelsHidden()
                .toggleStyle(.checkbox)

            Image(systemName: "globe")
                .foregroundColor(item.category.color)
                .frame(width: 20)

            Text(item.displayName)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(item.category.rawValue)
                .font(.body)
                .foregroundColor(item.category.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(item.category.color.opacity(0.10))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(item.category.color.opacity(0.30), lineWidth: 1.0))

            if service.config.blockedWebsites.contains(item.blockingName) {
                Button {
                    service.config.blockedWebsites.removeAll { $0 == item.blockingName }
                    service.saveConfig()
                    checked.remove(item.id)
                    items.removeAll { $0.id == item.id }
                    loadItems()
                } label: {
                    Image(systemName: "minus.circle.fill")
                        .foregroundColor(.red)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private let limitPresets = [(0, "Off"), (5, "5m"), (10, "10m"), (15, "15m"), (30, "30m"), (60, "1h"), (90, "90m"), (120, "2h")]
    private let limitCategories: [AppCategory] = [.entertainment, .social, .work, .development, .communication, .creative]

    private var limitsManager: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Daily screen-time alerts")
                    .font(.headline)
                Text("Get a notification when you exceed a category limit today. Resets at midnight.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            VStack(spacing: 0) {
                ForEach(Array(limitCategories.enumerated()), id: \.element.id) { index, category in
                    HStack(spacing: 12) {
                        Image(systemName: category.icon)
                            .frame(width: 20)
                            .foregroundColor(category.color)
                        Text(category.rawValue)
                            .font(.body)
                        Spacer()
                        Picker("", selection: limitBinding(category)) {
                            ForEach(limitPresets, id: \.0) { mins, label in
                                Text(label).tag(mins)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 90)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)

                    if index < limitCategories.count - 1 {
                        Divider().padding(.leading, 48)
                    }
                }
            }
            .appCard(cornerRadius: 14)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private func itemRow(_ item: BlockItem) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: selectionBinding(for: item))
            .labelsHidden()
            .toggleStyle(.checkbox)

            Group {
                if let img = item.icon {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit)
                } else if item.isApp {
                    Image(systemName: "app.fill").foregroundColor(.secondary)
                } else {
                    Image(systemName: "globe").foregroundColor(item.category.color)
                }
            }
            .frame(width: 20, height: 20)

            Text(item.displayName)
                .font(.body)
                .lineLimit(1)

            Spacer()

            Text(item.category.rawValue)
                .font(.body)
                .foregroundColor(item.category.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(item.category.color.opacity(0.10))
                .cornerRadius(5)
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(item.category.color.opacity(0.30), lineWidth: 1.0))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
    }

    // MARK: - Action bar

    private var checkedApps:  [String] { items.filter { checked.contains($0.id) && $0.isApp  }.map(\.blockingName) }
    private var checkedSites: [String] { items.filter { checked.contains($0.id) && !$0.isApp }.map(\.blockingName) }
    private var checkedTotal: Int { checkedApps.count + checkedSites.count }

    private var actionBar: some View {
        HStack(spacing: 18) {
            if step == .list {
                Button("Cancel", action: onCancel)
                    .buttonStyle(FooterCapsuleButtonStyle(kind: .secondary))

                Button("Next") {
                    step = .timer
                }
                .buttonStyle(FooterCapsuleButtonStyle(kind: .primary))
                .disabled(checkedTotal == 0)
            } else {
                Button("Back") {
                    step = .list
                    focusedTimeField = nil
                }
                .buttonStyle(FooterCapsuleButtonStyle(kind: .secondary))

                Button("Start") {
                    confirmAndStart()
                }
                .buttonStyle(FooterCapsuleButtonStyle(kind: .primary))
                .disabled(checkedTotal == 0)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .appWindowSurface()
    }

    private func confirmAndStart() {
        guard selectedMinutes > 0 else { return }
        focusedTimeField = nil

        guard selectedMinutes > 120 else {
            addSelectedMinutesToRecents()
            onStart(selectedMinutes, checkedApps, checkedSites)
            return
        }
        let h = selectedMinutes / 60
        let m = selectedMinutes % 60
        let label = m == 0 ? "\(h)h" : "\(h)h \(m)m"
        let alert = NSAlert()
        alert.messageText = "Start a \(label) session?"
        alert.informativeText = "This is a long session. Sessions cannot be cancelled once started."
        alert.addButton(withTitle: "Start")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            addSelectedMinutesToRecents()
            onStart(selectedMinutes, checkedApps, checkedSites)
        }
    }

    private func tabBackground(for step: SetupStep) -> some View {
        Capsule()
            .fill(tabFill(for: step))
            .padding(2)
    }

    private func tabForeground(for step: SetupStep) -> Color {
        self.step == step ? .primary : .secondary
    }

    private func tabFill(for step: SetupStep) -> Color {
        if self.step == step {
            return Color.white.opacity(0.16)
        }
        if hoveredStep == step {
            return Color.white.opacity(0.08)
        }
        return .clear
    }

    private func manageSectionBackground(for section: ManageSection) -> some View {
        Capsule()
            .fill(manageSectionFill(for: section))
            .padding(2)
    }

    private func manageSectionForeground(for section: ManageSection) -> Color {
        manageSection == section ? .primary : .secondary
    }

    private func manageSectionFill(for section: ManageSection) -> Color {
        if manageSection == section {
            return Color.white.opacity(0.16)
        }
        if hoveredManageSection == section {
            return Color.white.opacity(0.08)
        }
        return .clear
    }

    // MARK: - Data loading

    private var libraryAppItems: [BlockItem] {
        var merged: [String: BlockItem] = Dictionary(
            uniqueKeysWithValues: items.filter(\.isApp).map { ($0.id, $0) }
        )

        for app in AppScanner.shared.installedApps() {
            let item = BlockItem(
                displayName: app.name,
                blockingName: app.name,
                isApp: true,
                isFromConfig: false,
                todayDuration: merged["\(app.name):app"]?.todayDuration ?? 0,
                category: merged["\(app.name):app"]?.category ?? service.config.category(for: app.name),
                icon: merged["\(app.name):app"]?.icon ?? app.icon
            )
            merged[item.id] = item
        }

        return merged.values
            .filter { appSearch.isEmpty || $0.displayName.localizedCaseInsensitiveContains(appSearch) }
            .sorted(by: librarySort)
    }

    private var libraryWebsiteItems: [BlockItem] {
        items
            .filter { !$0.isApp }
            .filter { websiteSearch.isEmpty || $0.displayName.localizedCaseInsensitiveContains(websiteSearch) }
            .sorted(by: librarySort)
    }

    private func librarySort(_ lhs: BlockItem, _ rhs: BlockItem) -> Bool {
        let lhsSelected = checked.contains(lhs.id)
        let rhsSelected = checked.contains(rhs.id)
        if lhsSelected != rhsSelected { return lhsSelected && !rhsSelected }
        if lhs.todayDuration != rhs.todayDuration { return lhs.todayDuration > rhs.todayDuration }
        return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
    }

    private func selectionBinding(for item: BlockItem) -> Binding<Bool> {
        Binding(
            get: { checked.contains(item.id) },
            set: { isOn in
                if isOn {
                    if !items.contains(where: { $0.id == item.id }) {
                        items.append(item)
                    }
                    checked.insert(item.id)
                } else {
                    checked.remove(item.id)
                }
                syncConfigSelection(for: item, isSelected: isOn)
            }
        )
    }

    private func syncConfigSelection(for item: BlockItem, isSelected: Bool) {
        if item.isApp {
            if isSelected {
                if !service.config.blockedApps.contains(where: { $0.caseInsensitiveCompare(item.blockingName) == .orderedSame }) {
                    service.config.blockedApps.append(item.blockingName)
                }
            } else {
                service.config.blockedApps.removeAll { $0.caseInsensitiveCompare(item.blockingName) == .orderedSame }
            }
        } else {
            if isSelected {
                if !service.config.blockedWebsites.contains(item.blockingName) {
                    service.config.blockedWebsites.insert(item.blockingName, at: 0)
                }
            } else {
                service.config.blockedWebsites.removeAll { $0 == item.blockingName }
            }
        }
        service.saveConfig()
    }

    private func librarySearchField(
        placeholder: String,
        text: Binding<String>,
        onSubmit: (() -> Void)? = nil
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(placeholder, text: text)
                .textFieldStyle(.plain)
                .onSubmit {
                    onSubmit?()
                }
            if !text.wrappedValue.isEmpty {
                Button {
                    text.wrappedValue = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .appCard(cornerRadius: 12)
    }

    private static func initialConfigItems(from config: Config) -> [BlockItem] {
        let selfName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Lock In"

        let appItems = config.blockedApps.compactMap { appName -> BlockItem? in
            guard appName.caseInsensitiveCompare(selfName) != .orderedSame else { return nil }
            return BlockItem(
                displayName: appName,
                blockingName: appName,
                isApp: true,
                isFromConfig: true,
                todayDuration: 0,
                category: config.category(for: appName),
                icon: nil
            )
        }

        let websiteItems = config.blockedWebsites.map { domain in
            BlockItem(
                displayName: domain,
                blockingName: domain,
                isApp: false,
                isFromConfig: true,
                todayDuration: 0,
                category: config.category(for: domain),
                icon: nil
            )
        }

        return appItems + websiteItems
    }

    private func loadItems() {
        let config = service.config
        let store = ActivityStore.shared
        let selfName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "Lock In"
        let selfBundleID = Bundle.main.bundleIdentifier ?? ""
        isLoadingItems = true
        let existingItems = items
        let existingChecked = checked

        DispatchQueue.global(qos: .userInitiated).async {
            var result: [BlockItem] = []

            // Single dual-path query (works with Screen Time DB and custom JSONL)
            let topUsage = store.topApps(forDays: 1, limit: 50)
            var durationByName: [String: TimeInterval] = [:]
            var durationByDomain: [String: TimeInterval] = [:]
            var bundleIDByName: [String: String] = [:]
            for u in topUsage {
                if let domain = u.domain {
                    if let normalized = DomainMatcher.normalizeHost(domain) {
                        durationByDomain[normalized, default: 0] += u.duration
                    }
                } else {
                    durationByName[u.appName.lowercased(), default: 0] += u.duration
                    if !u.bundleID.isEmpty { bundleIDByName[u.appName.lowercased()] = u.bundleID }
                }
            }

            // Build name→icon map from installed apps (covers apps not used today)
            let installedByName: [String: AppInfo] = Dictionary(
                AppScanner.shared.installedApps().map { ($0.name.lowercased(), $0) },
                uniquingKeysWith: { first, _ in first }
            )

            func iconForApp(name: String, bundleID: String) -> NSImage? {
                if !bundleID.isEmpty,
                   let url = NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).first {
                    return NSWorkspace.shared.icon(forFile: url.path)
                }
                if let info = installedByName[name.lowercased()] {
                    return NSWorkspace.shared.icon(forFile: info.bundlePath)
                }
                return nil
            }

            // Config apps — exclude this app
            for appName in config.blockedApps where appName.caseInsensitiveCompare(selfName) != .orderedSame {
                let dur = durationByName[appName.lowercased()] ?? 0
                let bid = bundleIDByName[appName.lowercased()] ?? ""
                let cat = bid.isEmpty ? config.category(for: appName) : config.category(for: bid)
                result.append(BlockItem(
                    displayName: appName, blockingName: appName,
                    isApp: true, isFromConfig: true,
                    todayDuration: dur, category: cat,
                    icon: iconForApp(name: appName, bundleID: bid)
                ))
            }

            // Config websites
            for domain in config.blockedWebsites {
                let dur = durationByDomain.reduce(into: 0.0) { total, entry in
                    if DomainMatcher.matches(host: entry.key, blockedDomain: domain) {
                        total += entry.value
                    }
                }
                result.append(BlockItem(
                    displayName: domain, blockingName: domain,
                    isApp: false, isFromConfig: true,
                    todayDuration: dur, category: config.category(for: domain),
                    icon: nil
                ))
            }

            // Suggestions from today's usage — exclude this app and already-configured items
            let configAppNamesLower = Set(config.blockedApps.map { $0.lowercased() })
            let configWebsites = Set(config.blockedWebsites)
            for usage in topUsage where usage.duration >= 60
                && usage.bundleID != selfBundleID
                && usage.appName.caseInsensitiveCompare(selfName) != .orderedSame {
                let cat = config.category(for: ActivityStore.eventKey(
                    ActivityEvent(timestamp: .now, duration: 0, appName: usage.appName,
                                  bundleID: usage.bundleID, domain: usage.domain)
                ))
                guard cat == .entertainment || cat == .social else { continue }

                if let domain = usage.domain {
                    guard !configWebsites.contains(where: { DomainMatcher.matches(host: domain, blockedDomain: $0) }) else { continue }
                    result.append(BlockItem(
                        displayName: domain, blockingName: domain,
                        isApp: false, isFromConfig: false,
                        todayDuration: usage.duration, category: cat,
                        icon: nil
                    ))
                } else {
                    guard !configAppNamesLower.contains(usage.appName.lowercased()) else { continue }
                    result.append(BlockItem(
                        displayName: usage.appName, blockingName: usage.appName,
                        isApp: true, isFromConfig: false,
                        todayDuration: usage.duration, category: cat,
                        icon: iconForApp(name: usage.appName, bundleID: usage.bundleID)
                    ))
                }
            }

            DispatchQueue.main.async {
                let resultIDs = Set(result.map(\.id))
                let preservedItems = existingItems.filter { existingChecked.contains($0.id) && !resultIDs.contains($0.id) }
                self.items = result
                for item in preservedItems where !self.items.contains(where: { $0.id == item.id }) {
                    self.items.append(item)
                }
                if self.hasInitializedSelection {
                    let newIDs = Set(self.items.map(\.id))
                    let configIDs = Set(result.filter(\.isFromConfig).map(\.id))
                    self.checked = existingChecked.intersection(newIDs).union(configIDs)
                } else {
                    self.checked = Set(result.filter(\.isFromConfig).map(\.id))
                    self.hasInitializedSelection = true
                }
                self.isLoadingItems = false
            }
        }
    }

    private var normalizedWebsiteCandidate: String? {
        DomainMatcher.normalizeHost(websiteSearch.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func canAddWebsite(from rawText: String) -> Bool {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let site = DomainMatcher.normalizeHost(trimmed),
              site.contains(".") else { return false }
        return !service.config.blockedWebsites.contains(site)
    }

    private func addWebsiteFromSearch() {
        let candidate = websiteSearch.trimmingCharacters(in: .whitespacesAndNewlines)
        addWebsite(candidate)
    }

    private func addWebsite(_ rawWebsite: String) {
        guard let site = DomainMatcher.normalizeHost(rawWebsite) else {
            if !rawWebsite.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                websiteError = "Enter a valid domain (e.g. facebook.com)"
            }
            return
        }

        if service.config.blockedWebsites.contains(site) {
            websiteError = "\(site) is already in the list"
            return
        }
        guard site.contains(".") else {
            websiteError = "Enter a valid domain (e.g. facebook.com)"
            return
        }

        service.config.blockedWebsites.insert(site, at: 0)
        service.saveConfig()
        checked.insert("\(site):web")
        websiteSearch = ""
        websiteError = ""
        loadItems()
    }

    private func grantBrowserPermissions() {
        BlockerService.shared.presentBrowserPermissionSetupAlert()
    }

    private func checkForDeniedBrowsers() {
        let runningUnprimed = BlockerService.shared.knownBrowserBundleIDs.filter { bid in
            NSRunningApplication.runningApplications(withBundleIdentifier: bid).first != nil &&
            !BlockerService.shared.primedBrowserIDs.contains(bid)
        }
        guard !runningUnprimed.isEmpty else { return }

        BlockerService.shared.presentBrowserPermissionDeniedAlert(bundleIDs: runningUnprimed)
    }

    private func limitBinding(_ category: AppCategory) -> Binding<Int> {
        Binding(
            get: { service.config.categoryLimits[category.rawValue] ?? 0 },
            set: { mins in
                if mins == 0 {
                    service.config.categoryLimits.removeValue(forKey: category.rawValue)
                } else {
                    service.config.categoryLimits[category.rawValue] = mins
                }
                service.saveConfig()
            }
        )
    }

    private func addSelectedMinutesToRecents() {
        guard selectedMinutes > 0 else { return }
        let updated = Self.normalizedTimerPresets([selectedMinutes] + timerPresetOptions)
        service.updateTimerPresets(updated)
    }

    private func deleteSelectedPreset() {
        guard canDeleteSelectedPreset else { return }
        let updated = timerPresetOptions.filter { $0 != selectedMinutes }
        service.updateTimerPresets(Self.normalizedTimerPresets(updated))
    }

    private func selectPreset(_ minutes: Int) {
        selectedMinutes = minutes
        syncTimeFieldsFromSelection()
        focusedTimeField = nil
    }

    private func startPreset(_ minutes: Int) {
        selectPreset(minutes)
        confirmAndStart()
    }

    private func deletePreset(_ minutes: Int) {
        let updated = timerPresetOptions.filter { $0 != minutes }
        service.updateTimerPresets(Self.normalizedTimerPresets(updated))
    }

    private func presetCard(for minutes: Int) -> some View {
        let isSelected = selectedMinutes == minutes
        return VStack(spacing: 14) {
            Button {
                selectPreset(minutes)
            } label: {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.28), lineWidth: 4)
                        .frame(width: 108, height: 108)

                    VStack(spacing: 4) {
                        Text(Self.presetClockText(for: minutes))
                            .font(.system(size: 24, weight: .regular, design: .rounded))
                            .foregroundColor(.white.opacity(0.94))
                            .monospacedDigit()

                        Text(Self.presetDurationText(for: minutes))
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HStack {
                Button {
                    deletePreset(minutes)
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.55))
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    startPreset(minutes)
                } label: {
                    Image(systemName: "play.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 28, height: 28)
                        .background(Color.green)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(width: presetCardSize.width, height: presetCardSize.height)
        .background(
            RoundedRectangle(cornerRadius: presetCardCornerRadius, style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .clipShape(RoundedRectangle(cornerRadius: presetCardCornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: presetCardCornerRadius, style: .continuous)
                .stroke(isSelected ? blockSetupAccentBlue : Color.clear, lineWidth: 2)
        )
    }

    private func updateSelectedDuration(hours: String, minutes: String, seconds: String) {
        let normalized = TimerInputRules.normalized(hours: hours, minutes: minutes, seconds: seconds)

        hourInput = normalized.hoursText
        minuteInput = normalized.minutesText
        secondInput = normalized.secondsText
        selectedMinutes = normalized.totalMinutes
        customText = "\(selectedMinutes)"
    }

    private func syncTimeFieldsFromSelection() {
        let fields = TimerInputRules.fields(fromTotalMinutes: selectedMinutes)
        hourInput = fields.hoursText
        minuteInput = fields.minutesText
        secondInput = fields.secondsText
        customText = "\(selectedMinutes)"
    }

    private func timeLabel(_ text: String) -> some View {
        Text(text)
            .font(.title2.weight(.regular))
            .foregroundColor(.secondary)
            .frame(width: timerFieldWidth)
    }

    private var timeLabelSeparator: some View {
        Color.clear
            .frame(width: timerSeparatorWidth, height: 1)
    }

    private var timeSeparator: some View {
        Text(":")
            .font(.system(size: 98, weight: .thin, design: .rounded))
            .foregroundColor(.white.opacity(0.9))
            .offset(y: -8)
            .frame(width: timerSeparatorWidth)
    }

    private func timeField(_ binding: Binding<String>, field: TimerField) -> some View {
        SelectAllTimerTextField(text: binding, focusedField: $focusedTimeField, field: field)
            .frame(width: timerFieldWidth, height: timerFieldHeight)
            .background {
                if focusedTimeField == field {
                    RoundedRectangle(cornerRadius: timerSelectionCornerRadius, style: .continuous)
                        .fill(blockSetupAccentBlue)
                        .frame(width: timerSelectionWidth(for: binding.wrappedValue), height: timerSelectionHeight)
                        .allowsHitTesting(false)
                }
            }
    }

    private func timerSelectionWidth(for text: String) -> CGFloat {
        let displayText = text.isEmpty ? "00" : text
        let font = timerFieldFont()
        let width = (displayText as NSString).size(withAttributes: [.font: font]).width
        return min(timerFieldWidth, ceil(width) + 18)
    }

    private func timerFieldFont() -> NSFont {
        let baseFont = NSFont.systemFont(ofSize: 108, weight: .thin)
        if let descriptor = baseFont.fontDescriptor.withDesign(.rounded),
           let roundedFont = NSFont(descriptor: descriptor, size: 108) {
            return roundedFont
        }
        return baseFont
    }

    private static func normalizedTimerPresets(_ presets: [Int]) -> [Int] {
        let cleaned = presets
            .map { min(max($0, 1), 1440) }
            .reduce(into: [Int]()) { result, minutes in
                if !result.contains(minutes) {
                    result.append(minutes)
                }
            }
        return cleaned.isEmpty ? defaultTimerPresets : cleaned
    }

    private static func presetClockText(for minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 {
            return String(format: "%02d:%02d", hours, mins)
        }
        return String(format: "%02d:00", mins)
    }

    private static func presetDurationText(for minutes: Int) -> String {
        let hours = minutes / 60
        let mins = minutes % 60
        if hours > 0 && mins > 0 {
            return "\(hours) hr \(mins) min"
        }
        if hours > 0 {
            return hours == 1 ? "1 hr" : "\(hours) hr"
        }
        return "\(minutes) min"
    }
}

// MARK: - Supporting types

private struct SelectAllTimerTextField: NSViewRepresentable {
    @Binding var text: String
    @Binding var focusedField: TimerField?
    let field: TimerField

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> SelectAllNSTextField {
        let textField = SelectAllNSTextField()
        textField.delegate = context.coordinator
        textField.formatter = TimerDigitsFormatter()
        textField.isBordered = false
        textField.isBezeled = false
        textField.drawsBackground = false
        textField.isEditable = true
        textField.isSelectable = true
        textField.focusRingType = .none
        textField.alignment = .center
        textField.font = .systemFont(ofSize: 108, weight: .thin)
        if let descriptor = textField.font?.fontDescriptor.withDesign(.rounded) {
            textField.font = NSFont(descriptor: descriptor, size: 108)
        }
        textField.textColor = NSColor.white.withAlphaComponent(0.9)
        textField.maximumNumberOfLines = 1
        textField.lineBreakMode = .byClipping
        textField.usesSingleLineMode = true
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        textField.stringValue = text
        textField.onFocus = {
            focusedField = field
        }
        return textField
    }

    func updateNSView(_ nsView: SelectAllNSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if let editor = nsView.currentEditor(), editor.string != text {
            editor.string = text
            editor.selectedRange = NSRange(location: text.count, length: 0)
        }
        nsView.onFocus = {
            focusedField = field
        }
        nsView.applyEditorAppearance()

        if focusedField == field,
           let window = nsView.window,
           window.firstResponder !== nsView,
           window.firstResponder !== nsView.currentEditor() {
            window.makeFirstResponder(nsView)
            DispatchQueue.main.async {
                guard focusedField == field else { return }
                nsView.applyEditorAppearance()
            }
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: SelectAllTimerTextField

        init(_ parent: SelectAllTimerTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let textField = notification.object as? NSTextField else { return }
            let resolved = TimerInputRules.resolvedTextAfterEditing(
                currentText: parent.text,
                proposedText: textField.stringValue
            )
            if textField.stringValue != resolved {
                textField.stringValue = resolved
                if let editor = textField.currentEditor() {
                    editor.string = resolved
                    editor.selectAll(nil)
                }
            }
            parent.text = resolved
        }

        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.focusedField = parent.field
            guard let textField = notification.object as? SelectAllNSTextField else { return }
            DispatchQueue.main.async {
                textField.applyEditorAppearance()
            }
        }
    }
}

private final class TimerDigitsFormatter: Formatter {
    override func string(for obj: Any?) -> String? {
        guard let string = obj as? String else { return nil }
        return TimerInputRules.sanitize(string)
    }

    override func getObjectValue(
        _ obj: AutoreleasingUnsafeMutablePointer<AnyObject?>?,
        for string: String,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        obj?.pointee = TimerInputRules.sanitize(string) as NSString
        return true
    }

    override func isPartialStringValid(
        _ partialStringPtr: AutoreleasingUnsafeMutablePointer<NSString>,
        proposedSelectedRange proposedSelRangePtr: NSRangePointer?,
        originalString origString: String,
        originalSelectedRange origSelRange: NSRange,
        errorDescription error: AutoreleasingUnsafeMutablePointer<NSString?>?
    ) -> Bool {
        let partialString = partialStringPtr.pointee as String
        let resolved = TimerInputRules.validatedPartialString(
            originalText: origString,
            proposedText: partialString
        )
        guard resolved != partialString else { return true }
        partialStringPtr.pointee = resolved as NSString
        proposedSelRangePtr?.pointee = origSelRange
        return false
    }
}

private final class SelectAllNSTextField: NSTextField {
    var onFocus: (() -> Void)?

    func applyEditorAppearance() {
        guard let editor = currentEditor() as? NSTextView else { return }
        editor.insertionPointColor = .clear
        editor.backgroundColor = .clear
        editor.drawsBackground = false
        editor.selectedTextAttributes = [
            .backgroundColor: NSColor.clear,
            .foregroundColor: NSColor.white.withAlphaComponent(0.95)
        ]
    }

    override func becomeFirstResponder() -> Bool {
        let becameFirstResponder = super.becomeFirstResponder()
        if becameFirstResponder {
            DispatchQueue.main.async { [weak self] in
                self?.applyEditorAppearance()
            }
        }
        return becameFirstResponder
    }

    override func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        DispatchQueue.main.async { [weak self] in
            self?.onFocus?()
            self?.applyEditorAppearance()
            self?.currentEditor()?.selectAll(nil)
        }
    }
}

private struct BlockItem: Identifiable {
    let displayName: String
    let blockingName: String
    let isApp: Bool
    let isFromConfig: Bool
    let todayDuration: TimeInterval
    let category: AppCategory
    let icon: NSImage?

    var id: String { blockingName + (isApp ? ":app" : ":web") }
}

private struct FooterCapsuleButtonStyle: ButtonStyle {
    enum Kind {
        case primary
        case secondary
    }

    let kind: Kind

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .frame(minWidth: 78)
            .frame(height: 25)
            .padding(.horizontal, 13)
            .foregroundColor(foregroundColor(isPressed: configuration.isPressed))
            .background(backgroundColor(isPressed: configuration.isPressed))
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }

    private func backgroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return isPressed ? blockSetupAccentBlue.opacity(0.86) : blockSetupAccentBlue
        case .secondary:
            return isPressed ? Color.white.opacity(0.14) : Color.white.opacity(0.10)
        }
    }

    private func foregroundColor(isPressed: Bool) -> Color {
        switch kind {
        case .primary:
            return .white
        case .secondary:
            return isPressed ? .primary.opacity(0.92) : .primary
        }
    }
}
