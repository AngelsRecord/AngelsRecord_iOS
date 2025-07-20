//
//  RecordListView.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI
import SwiftData

struct RecordListView: View {
    @EnvironmentObject var viewModel: RecordListViewModel
    @Environment(\.modelContext) private var modelContext
    @State private var isRefreshing = false

    var body: some View {
        NavigationView {
            Group {
                if viewModel.isLoadingEpisodes {
                    VStack {
                        ProgressView("에피소드 불러오는 중...")
                            .progressViewStyle(CircularProgressViewStyle())
                            .padding(.top, 100)
                        Spacer()
                    }
                } else {
                    List(viewModel.episodes) { episode in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(episode.title)
                                .font(.headline)

                            Text(episode.desc)
                                .font(.subheadline)
                                .foregroundColor(.secondary)

                            Text("업로드: \(formatted(date: episode.uploadedAt))")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        .padding(.vertical, 8)
                    }
                }
            }
            .navigationTitle("에피소드 목록")
            .refreshable {
                viewModel.fetchAndSyncEpisodes(context: modelContext)
            }
            .onAppear {
                viewModel.loadLocalEpisodes(context: modelContext)
            }
        }
    }

    private func formatted(date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.locale = Locale(identifier: "ko_KR")
        return formatter.string(from: date)
    }
}

#Preview {
    RecordListView()
        .environmentObject(RecordListViewModel()) // 프리뷰용
}
