//
//  DownloadLodingIndicator.swift
//  A'Cast
//
//  Created by Seungeun Park on 9/14/25.
//

import SwiftUI

struct DownloadLoadingIndicator: View {
    @EnvironmentObject var recordListViewModel: RecordListViewModel
    let episode: EpisodeModel
    
    var body: some View {
        
        if recordListViewModel.isDownloading(fileName: episode.fileName) {
            let p = recordListViewModel.progress(for: episode.fileName)
            if p <= 0.0001 {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            } else {
                ring(progress: p)
            }
        } else if recordListViewModel.isDownloaded(episode) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 12))
                .foregroundColor(.subText)
        } else {
            EmptyView()
        }
    }
    
    @ViewBuilder
    private func ring(progress: Double) -> some View {
        ZStack {
            Circle()
                .stroke(.subText, lineWidth: 2)
                .frame(width: 12, height: 12)
            
            Circle()
                .trim(from: 0, to: min(max(progress, 0),1))
                .stroke(.mainBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .frame(width: 12, height: 12)
                .animation(.linear(duration: 2), value: progress)
        }
    }
}

