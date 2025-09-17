//
//  ExampleEpDownBadge.swift
//  A'Cast
//
//  Created by 성현 on 9/15/25.
//

// 개별 다운로드 로직때문에 만든 임시파일입니다. 추후에 제거하고 새 컴포넌트로 교체 예정

import SwiftUI

struct ExampleEpDownBadge: View {
    @EnvironmentObject var recordListViewModel: RecordListViewModel
    let episode: EpisodeModel

    // 스타일
    var size: CGFloat = 12
    var lineWidth: CGFloat = 2
    var startSymbol: String = "S"
    var doneSymbol: String = "C"

    var body: some View {
        if recordListViewModel.isDownloading(fileName: episode.fileName) {
            // 다운로드 시작 직후(진행률 0)엔 S, 0보다 크면 링
            let p = recordListViewModel.progress(for: episode.fileName)
            if p <= 0.0001 {
                Text(startSymbol)
                    .font(Font.SFPro.SemiBold.s12)
            } else {
                ring(progress: p)
            }
        } else if recordListViewModel.isDownloaded(episode) {
            Text(doneSymbol)
                .font(Font.SFPro.SemiBold.s12)
        } else {
            // 아무 상태도 없으면 표시하지 않음
            EmptyView()
        }
    }

    @ViewBuilder
    private func ring(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(Color.gray.opacity(0.25), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(Color.accentColor,
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.1), value: progress)
        }
        .frame(width: size, height: size)
    }
}
