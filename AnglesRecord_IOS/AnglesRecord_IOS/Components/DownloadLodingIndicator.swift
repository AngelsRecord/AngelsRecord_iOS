//
//  DownloadLodingIndicator.swift
//  A'Cast
//
//  Created by Seungeun Park on 9/14/25.
//

import SwiftUI

struct DownloadLoadingIndicator: View {
    @State private var isDownloading = false
    @State private var progress: CGFloat = 0
    @State private var isCompleted = false
    
    var body: some View {
        Button(action: startDownload) {
            if isCompleted {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 12))
                    .foregroundColor(.subText)
            } else if isDownloading {
                ZStack {
                        Circle()
                        .stroke(.subText, lineWidth: 2)
                        .frame(width: 12, height: 12)
                    
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(.mainBlue, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 12, height: 12)
                }
            } else {
                Image(systemName: "circle.dashed")
                    .font(.system(size: 12))
                    .foregroundColor(.gray)
            }
        }
        .buttonStyle(.plain)
    }
    
    private func startDownload() {
        guard !isDownloading && !isCompleted else { return }
        isDownloading = true
        progress = 0
        
        withAnimation(.linear(duration: 2)) {
            progress = 1.0
        }
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            isDownloading = false
            isCompleted = true
        }
    }
}

#Preview {
    DownloadLoadingIndicator()
}
