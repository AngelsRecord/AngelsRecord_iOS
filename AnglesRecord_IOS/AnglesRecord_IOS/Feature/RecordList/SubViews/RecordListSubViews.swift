import SwiftUI

struct RecordCardView: View {
    let record: RecordListModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(record.title)
                    .font(.headline)
                    .lineLimit(1)
                
                Spacer()
                
                Text(record.formattedDuration)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            HStack {
                Text(record.artist)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                
                Spacer()
                
                Text(record.formattedDate)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(Color(UIColor.secondarySystemBackground))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}
