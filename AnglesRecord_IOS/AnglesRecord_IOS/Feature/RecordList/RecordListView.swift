//
//  RecordListView.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import SwiftData

private func TS() -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    return f.string(from: Date())
}

struct RecordListView: View {
    @EnvironmentObject var viewModel: RecordListViewModel
    @Environment(\.modelContext) private var modelContext

    /// AppDelegate가 올리는 자동 새로고침 플래그
    @AppStorage("shouldFetchNewEpisodes") private var shouldFetchNewEpisodes: Bool = false

    @State private var isRefreshing = false

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoadingEpisodes && viewModel.episodes.isEmpty {
                    VStack {
                        Text("에피소드 불러오는 중...")
                            .padding(.top, 100)
                        Spacer()
                    }
                } else {
                    List(viewModel.episodes) { episode in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title).font(.headline)
                            Text(episode.desc).font(.subheadline).foregroundColor(.secondary)
                            Text("업로드: \(formatted(date: episode.uploadedAt))")
                                .font(.caption).foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("에피소드 목록")
            .refreshable {
                await refreshNow(trigger: "pull-to-refresh")
            }
            .onAppear {
                print("👀 [\(TS())] RecordListView.onAppear")
                // 로컬 먼저 그림
                viewModel.loadLocalEpisodes(context: modelContext)
                // 플래그가 이미 올라와 있으면 즉시 새로고침
                if shouldFetchNewEpisodes {
                    Task { await refreshNow(trigger: "onAppear-flag") }
                }
            }
            .onChange(of: shouldFetchNewEpisodes) { newValue in
                print("🔁 [\(TS())] shouldFetchNewEpisodes 변경: \(newValue)")
                if newValue {
                    Task { await refreshNow(trigger: "flag-onchange") }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
                print("🔔 [\(TS())] didBecomeActive 수신, flag=\(shouldFetchNewEpisodes)")
                if shouldFetchNewEpisodes {
                    Task { await refreshNow(trigger: "didBecomeActive") }
                }
            }
        }
    }

    private func refreshNow(trigger: String) async {
        guard !isRefreshing else {
            print("⏳ [\(TS())] refreshNow(\(trigger)) SKIP: 이미 새로고침 중")
            return
        }
        isRefreshing = true
        print("🚀 [\(TS())] refreshNow 시작 by \(trigger)")

        await withCheckedContinuation { cont in
            viewModel.fetchAndSyncEpisodes(context: modelContext) { ok in
                print("🧩 [\(TS())] fetchAndSyncEpisodes 완료 ok=\(ok)")
                // 완료 이후 살짝 늦춰서 UI 반영 여유
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    cont.resume()
                }
            }
        }

        // 한 번만 자동 새로고침 되도록 플래그 내리기
        if shouldFetchNewEpisodes {
            print("✅ [\(TS())] 플래그 OFF")
            shouldFetchNewEpisodes = false
        }

        isRefreshing = false
        print("🏁 [\(TS())] refreshNow 종료")
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}
