import SwiftUI

struct SystemIntelligenceToAppVerificationView: View {
    private let content = SystemExperienceContent.content(for: .appIntents)
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var history = SMSAppIntentHistoryStore.shared
    @State private var state: DemoLiveActivityAttributes.ContentState?
    @State private var selectedSample: SMSIncomingSample?
    @State private var classification: SMSIncomingClassification?
    @State private var isLaunching = false
    @State private var modelLatency: String?
    @State private var runtimeDiagnostic: String?

    var body: some View {
        systemPage(content, showsIntroDescription: false, showsFooter: false) {
            VStack(alignment: .leading, spacing: 14) {
                Text("触发历史")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)

                if history.entries.isEmpty {
                    Color.clear
                        .frame(height: 56)
                } else {
                    ForEach(history.entries) { entry in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(entry.receivedAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                            Text("短信原文")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.secondaryInk)
                            Text(entry.text)
                                .textSelection(.enabled)
                            Divider()
                            Text(entry.title)
                                .font(.headline)
                            Text(entry.summary)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                        .padding(14)
                        .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }

                Divider().padding(.vertical, 6)

                Text("随机短信演示")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(AppTheme.ink)

                Text("随机抽取一条内置脱敏短信，分析后创建最终实况窗。此演示不会写入上方的 App Intent 历史。")
                    .font(.subheadline)
                    .foregroundStyle(AppTheme.secondaryInk)

                Button {
                    selectRandomSMS()
                } label: {
                    Label("随机短信", systemImage: "shuffle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLaunching)

                if let selectedSample {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("已选短信")
                            .font(.headline)
                        Text(selectedSample.text)
                            .font(.body)
                            .textSelection(.enabled)
                    }
                    .padding(14)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button {
                    Task { await analyzeSelectedSMS() }
                } label: {
                    Label("分析并显示通知", systemImage: "sparkles")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedSample == nil || isLaunching)

                if isLaunching {
                    ProgressView("正在使用端侧模型分析短信…")
                }

                if let state, let classification {
                    ResultSurface(
                        title: "已发送的实况窗状态",
                        text: "分类：\(classification.category.rawValue)\n\(state.title)\n\(state.summary)"
                    )
                }

                if let modelLatency {
                    HStack {
                        Text("端侧模型耗时")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(AppTheme.ink)
                        Spacer()
                        Text(modelLatency)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryInk)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .background(.white.opacity(0.82), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let runtimeDiagnostic {
                    ResultSurface(title: "ActivityKit 运行诊断", text: runtimeDiagnostic)
                }

                Button("重置验证") {
                    state = nil
                    classification = nil
                    selectedSample = nil
                    modelLatency = nil
                    runtimeDiagnostic = nil
                }
                .buttonStyle(.bordered)
            }
            .onAppear { history.reload() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { history.reload() }
            }
        }
    }

    @MainActor
    private func selectRandomSMS() {
        do {
            selectedSample = try SMSIncomingSamplePool.bundled().randomSample()
            classification = nil
            state = nil
            modelLatency = nil
            runtimeDiagnostic = nil
        } catch {
            runtimeDiagnostic = "sampleError:\(String(describing: error))"
        }
    }

    @MainActor
    private func analyzeSelectedSMS() async {
        guard let selectedSample else { return }
        isLaunching = true
        defer { isLaunching = false }
        let clock = ContinuousClock()
        let startedAt = clock.now
        do {
            let result = try await SMSIncomingClassificationService().classify(selectedSample.text)
            let liveActivityState = RunOnDeviceModelIntent.liveActivityState(for: result)
            await DemoLiveActivityCoordinator.shared.update(liveActivityState)
            classification = result
            state = liveActivityState
            modelLatency = startedAt.duration(to: clock.now).formatted(.units(allowed: [.seconds], width: .narrow))
            runtimeDiagnostic = await DemoLiveActivityCoordinator.shared.diagnostic() ?? "activityStateSent"
        } catch {
            await DemoLiveActivityCoordinator.shared.endActive()
            runtimeDiagnostic = "error:\(String(describing: error))"
        }
    }
}
