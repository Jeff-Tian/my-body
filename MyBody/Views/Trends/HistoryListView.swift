import SwiftUI

struct HistoryListView: View {
    let records: [InBodyRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("历史记录")
                .font(.headline)
                .padding(.horizontal)

            if records.isEmpty {
                Text("暂无记录")
                    .foregroundColor(.secondary)
                    .font(.subheadline)
                    .padding(.horizontal)
            } else {
                ForEach(records, id: \.id) { record in
                    NavigationLink(destination: DetailView(record: record)) {
                        HistoryRow(record: record)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct HistoryRow: View {
    let record: InBodyRecord

    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            if let data = record.photoData, let uiImage = UIImage(data: data) {
                Image(uiImage: uiImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.appGreen.opacity(0.1))
                    .frame(width: 50, height: 50)
                    .overlay {
                        Image(systemName: "doc.text")
                            .foregroundColor(.appGreen)
                    }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(record.formattedDate)
                    .font(.subheadline)
                    .fontWeight(.medium)
                if let weight = record.weight {
                    Text("体重 \(weight.formatted1) kg")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if let score = record.inbodyScore {
                VStack(spacing: 2) {
                    Text("\(score)")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(scoreColor(score))
                    Text("分")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    private func scoreColor(_ score: Int) -> Color {
        if score >= 80 { return .appGreen }
        if score >= 60 { return .appOrange }
        return .appRed
    }
}
