import Foundation
import PhotosUI

enum PhotoPickerError: Error {
    case cancelled
    case unsupportedItem
    case fileTooLarge
}

struct PhotoPickerAdapter {
    let draftDirectory: URL

    /// 写真選択の一時結果を下書き領域へ移し、選択元のURL寿命から切り離す。
    func importItem(_ item: PhotosPickerItem?) async throws -> URL {
        guard let item else { throw PhotoPickerError.cancelled }
        guard let data = try await item.loadTransferable(type: Data.self) else {
            throw PhotoPickerError.unsupportedItem
        }
        guard data.count <= 30 * 1024 * 1024 else { throw PhotoPickerError.fileTooLarge }
        try FileManager.default.createDirectory(at: draftDirectory, withIntermediateDirectories: true)
        let file = draftDirectory.appendingPathComponent(UUID().uuidString + ".source")
        try data.write(to: file, options: .atomic)
        return file
    }
}
