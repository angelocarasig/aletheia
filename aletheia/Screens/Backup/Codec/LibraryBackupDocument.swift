//
//  LibraryBackupDocument.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI
import UniformTypeIdentifiers

// ReadConfiguration exists only because FileDocument requires it - import
// goes through .fileImporter instead, never this read path
struct LibraryBackupDocument: FileDocument, Equatable {
    static var readableContentTypes: [UTType] { [.aletheiaBackup] }

    let data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else {
            throw CocoaError(.fileReadCorruptFile)
        }
        self.data = data
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

extension UTType {
    // matches the UTExportedTypeDeclarations entry in Info.plist
    static let aletheiaBackup = UTType(exportedAs: "moe.aletheia.backup")
}
