import SlipsCore

/// The adapter for each destination type. Types without one yet keep their rows waiting.
enum DestinationAdapters {
    @Sendable static func make(_ destination: Destination) -> (any DestinationAdapter)? {
        switch destination.type {
        case .icloud: ICloudAdapter()
        case .folder: FolderAdapter(destination: destination)
        case .webdav:
            WebDAVConfig(destination: destination, password: Keychain.get(destination.id) ?? "").map {
                WebDAVClient(config: $0, transport: AppHTTPTransport(), localize: catalogLocalize)
            }
        case .library, .fin, .dropbox, .onedrive, .gdrive: nil
        }
    }
}
