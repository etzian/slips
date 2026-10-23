import SlipsCore

/// The adapter for each destination type. Types without one yet keep their rows waiting.
enum DestinationAdapters {
    @Sendable static func make(_ destination: Destination) -> (any DestinationAdapter)? {
        switch destination.type {
        case .icloud: ICloudAdapter()
        case .folder: FolderAdapter(destination: destination)
        case .library, .webdav, .fin, .dropbox, .onedrive, .gdrive: nil
        }
    }
}
