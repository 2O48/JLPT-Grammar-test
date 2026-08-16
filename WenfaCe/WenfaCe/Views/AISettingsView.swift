import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct AISettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AISettingsStore
    @Query(sort: \PracticeRecord.createdAt, order: .reverse) private var records: [PracticeRecord]
    @Query(sort: \GrammarFavorite.createdAt, order: .reverse) private var favorites: [GrammarFavorite]

    @State private var backupDocument: WenfaCeBackupDocument?
    @State private var isShowingExporter = false
    @State private var isShowingImporter = false
    @State private var alert: SettingsAlert?
    @FocusState private var focusedField: SettingsField?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(settings.isConfigured ? "AI 已配置" : "AI 未配置", systemImage: settings.isConfigured ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(settings.isConfigured ? .green : .secondary)
                } footer: {
                    Text("练习记录、收藏和 API Token 会通过 iCloud 同步；其余设置可通过备份文件在设备间迁移。")
                }

                Section("OpenAI 兼容接口") {
                    TextField("API 地址", text: $settings.baseURL)
                        .wenfaURLInput()
                        .focused($focusedField, equals: .baseURL)
                    TextField("模型名称", text: $settings.model)
                        .wenfaAPIInput()
                        .focused($focusedField, equals: .model)
                    SecureField("API Token", text: $settings.token)
                        .wenfaAPIInput()
                        .focused($focusedField, equals: .token)
                }

                Section("附加指令") {
                    TextEditor(text: $settings.instruction)
                        .frame(minHeight: 100)
                        .focused($focusedField, equals: .instruction)
                }

                Section {
                    Button("保存设置") { save() }
                    if let lastSyncDate = settings.lastSyncDate {
                        LabeledContent("最近同步时间") {
                            Text(lastSyncDate.formatted(date: .abbreviated, time: .shortened))
                        }
                        .foregroundStyle(.secondary)
                    } else {
                        LabeledContent("最近同步时间", value: "尚未同步")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("每次保存会以最新内容覆盖所有设备上的旧设置。")
                }

                Section {
                    Button {
                        exportBackup()
                    } label: {
                        Label("导出设置与进度", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isShowingImporter = true
                    } label: {
                        Label("导入设置与进度", systemImage: "square.and.arrow.down")
                    }
                } header: {
                    Text("备份")
                } footer: {
                    Text("备份包含 API Token、练习记录和收藏，请妥善保管文件。导入会合并未存在的记录和收藏，并恢复备份中的 AI 设置。")
                }
            }
            .navigationTitle("AI 设置")
            .fileExporter(
                isPresented: $isShowingExporter,
                document: backupDocument,
                contentType: .json,
                defaultFilename: "WenfaCe-Backup"
            ) { result in
                if case let .failure(error) = result {
                    showError("无法导出备份：\(error.localizedDescription)")
                }
            }
            .fileImporter(isPresented: $isShowingImporter, allowedContentTypes: [.json]) { result in
                switch result {
                case let .success(url):
                    importBackup(from: url)
                case let .failure(error):
                    showError("无法导入备份：\(error.localizedDescription)")
                }
            }
            .alert(item: $alert) { alert in
                Alert(
                    title: Text(alert.title),
                    message: Text(alert.message),
                    dismissButton: .default(Text("好"))
                )
            }
        }
    }

    private func save() {
        focusedField = nil
        do {
            try settings.save()
            alert = SettingsAlert(title: "已保存", message: "最新设置已提交到 iCloud，并会覆盖旧设置。")
        } catch {
            showError("设置同步失败：\(error.localizedDescription)")
        }
    }

    private func exportBackup() {
        do {
            let data = try WenfaCeBackup(settings: settings, records: records, favorites: favorites).encoded()
            backupDocument = WenfaCeBackupDocument(data: data)
            isShowingExporter = true
        } catch {
            showError("无法创建备份：\(error.localizedDescription)")
        }
    }

    private func importBackup(from url: URL) {
        let didAccess = url.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        do {
            let backup = try WenfaCeBackup.decode(Data(contentsOf: url))
            let summary = try backup.apply(to: modelContext, settingsStore: settings)
            alert = SettingsAlert(
                title: "导入完成",
                message: "已恢复 AI 设置，新增 \(summary.records) 条练习记录和 \(summary.favorites) 条收藏。"
            )
        } catch {
            showError("无法导入备份：\(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        alert = SettingsAlert(title: "操作未完成", message: message)
    }
}

private enum SettingsField: Hashable {
    case baseURL
    case model
    case token
    case instruction
}

private extension View {
    @ViewBuilder
    func wenfaAPIInput() -> some View {
#if os(iOS)
        textInputAutocapitalization(.never)
            .autocorrectionDisabled()
#else
        self
#endif
    }

    @ViewBuilder
    func wenfaURLInput() -> some View {
#if os(iOS)
        textInputAutocapitalization(.never)
            .keyboardType(.URL)
            .autocorrectionDisabled()
#else
        self
#endif
    }
}

struct WenfaCeBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

private struct SettingsAlert: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}
