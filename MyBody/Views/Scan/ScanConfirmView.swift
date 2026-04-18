import SwiftUI

struct ScanConfirmView: View {
    @Bindable var viewModel: ScanViewModel
    let onConfirm: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Text("找到 \(viewModel.scannedPhotos.count) 张疑似 InBody 报告")
                .font(.headline)
                .padding(.top)

            Text("请选择要导入的报告照片")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ScrollView {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12)
                ], spacing: 12) {
                    ForEach(viewModel.scannedPhotos) { photo in
                        PhotoThumbnailView(photo: photo) {
                            viewModel.toggleSelection(for: photo)
                        }
                    }
                }
                .padding()
            }

            HStack(spacing: 16) {
                Text("已选择 \(viewModel.selectedPhotos.count) 张")
                    .foregroundColor(.secondary)
                    .font(.subheadline)

                Spacer()

                Button {
                    onConfirm()
                } label: {
                    Text("开始识别")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background(
                            viewModel.selectedPhotos.isEmpty
                            ? Color.gray
                            : Color.appGreen
                        )
                        .clipShape(Capsule())
                }
                .disabled(viewModel.selectedPhotos.isEmpty)
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }
}

struct PhotoThumbnailView: View {
    let photo: ScannedPhoto
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                if let thumb = photo.thumbnail {
                    Image(uiImage: thumb)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.gray.opacity(0.2))
                        .frame(height: 120)
                }

                Image(systemName: photo.isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(photo.isSelected ? .appGreen : .gray)
                    .font(.title3)
                    .padding(6)
            }
            .overlay {
                if photo.isSelected {
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Color.appGreen, lineWidth: 2)
                }
            }
        }
        .buttonStyle(.plain)
    }
}
