//
//  PlayListView.swift
//  AnglesRecord_IOS
//
//
//

import SwiftUI

struct PlayListView: View {
    public let record: RecordListModel

    var body: some View {
        HStack(spacing: 12) {
            Image("mainimage_yet")
                .resizable()
                .frame(width: 44, height: 44)
                .cornerRadius(4)

            VStack(alignment: .leading, spacing: 4) {
                Text(record.title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                Text(record.formattedDate)
                    .font(.caption)
                    .foregroundColor(.gray)
            }

            Spacer()

            Image(systemName: "line.3.horizontal")
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    PlayListView(
        record: RecordListModel(
            title: "녹음 제목 예시",
            artist: "엔젤스",
            duration: 180,
            fileURL: nil
        )
    )
}
