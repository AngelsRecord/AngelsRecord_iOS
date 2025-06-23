//
//  RecordListView.swift
//  AnglesRecord_IOS
//
//  Created by 성현 on 6/22/25.
//

import SwiftUI

struct RecordListView: View {
    @StateObject private var viewModel = RecordListViewModel()

    var body: some View {
        NavigationView {
            List(viewModel.episodes) { episode in
                VStack(alignment: .leading, spacing: 4) {
                    Text(episode.title)
                        .font(.headline)

                    Text(episode.description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Text("업로드: \(formatted(date: episode.uploadDate))")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                .padding(.vertical, 8)
            }
            .navigationTitle("에피소드 목록")
        }
        .onAppear {
            viewModel.fetchEpisodes()
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
}
