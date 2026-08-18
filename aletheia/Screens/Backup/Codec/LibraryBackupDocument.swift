//
//  LibraryBackupDocument.swift
//  aletheia
//
//  Created by Angelo Carasig on 18/8/26.
//

import SwiftUI
import UniformTypeIdentifiers

// the FileDocument .fileExporter needs - a thin wrapper around the already-
// encoded backup blob (LibraryBackupCodec.encode already did the real
// work: build, serialize, envelope-wrap, compress). ReadConfiguration is
// only implemented because the protocol requires it; nothing in this app
// opens a backup file through FileDocument's own read path - import goes
// through AletheiaBackupImportScreen's .fileImporter instead
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
    // matches the UTExportedTypeDeclarations entry in Info.plist exactly -
    // that declaration is what makes Files, the export picker, and any
    // future "open in Aletheia" handler all agree on what this identifier
    // means, rather than each side synthesizing its own ad-hoc type
    static let aletheiaBackup = UTType(exportedAs: "moe.aletheia.backup")
}
