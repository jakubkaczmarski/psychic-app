import SwiftUI
import UIKit

/// Psychic photos set in Psychic Studio, downloaded once and kept on the phone.
///
/// The server says which version of each psychic's photo is current (`GET /v1/psychics`, a few bytes).
/// A photo is downloaded only when its version differs from the one saved here, so the app doesn't
/// fetch photos on every launch, and they keep working offline. Without a downloaded photo, or when
/// the server has none, the photo built into the app is used.
@MainActor
final class PsychicPhotos: ObservableObject {
    static let shared = PsychicPhotos()

    @Published private(set) var downloaded: [String: UIImage] = [:]

    /// Psychic id -> version of the photo saved on the phone.
    private var versions: [String: String]
    private let folder: URL
    private var syncing = false

    private init() {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        folder = support.appendingPathComponent("PsychicPhotos", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let saved = (try? Data(contentsOf: folder.appendingPathComponent("versions.json")))
            .flatMap { try? JSONDecoder().decode([String: String].self, from: $0) } ?? [:]
        versions = [:]
        for (id, version) in saved {
            if let image = UIImage(contentsOfFile: file(for: id).path) {
                downloaded[id] = image
                versions[id] = version
            }
        }
    }

    /// The studio photo if one has been downloaded, otherwise the one built into the app.
    func image(for psychic: Psychic) -> UIImage? {
        downloaded[psychic.id] ?? UIImage(named: psychic.imageName)
    }

    /// Saves the list of psychics (see `PsychicDirectory`) and downloads photos whose version changed.
    /// If the server can't be reached, keeps what's saved. Returns whether the list of psychics changed.
    @discardableResult
    func sync(baseURL: URL) async -> Bool {
        guard !syncing else { return false }
        syncing = true
        defer { syncing = false }

        struct Listing: Decodable {
            struct Entry: Decodable { let id: String; let photo: String? }
            let psychics: [Entry]
        }
        struct Directory: Decodable { let psychics: [PsychicDirectory.Entry] }
        var request = URLRequest(url: baseURL.appendingPathComponent("v1/psychics"))
        request.timeoutInterval = 8
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let listing = try? JSONDecoder().decode(Listing.self, from: data) else { return false }
        let changed = (try? JSONDecoder().decode(Directory.self, from: data)).map { PsychicDirectory.update($0.psychics) } ?? false

        for entry in listing.psychics where Self.isSafeID(entry.id) {
            guard let version = entry.photo else {
                remove(entry.id) // no studio photo: back to the built-in one
                continue
            }
            if versions[entry.id] == version { continue }

            var components = URLComponents(
                url: baseURL.appendingPathComponent("v1/psychics/\(entry.id)/photo"), resolvingAgainstBaseURL: false)
            components?.queryItems = [URLQueryItem(name: "v", value: version)]
            guard let url = components?.url,
                  let (bytes, photoResponse) = try? await URLSession.shared.data(from: url),
                  (photoResponse as? HTTPURLResponse)?.statusCode == 200,
                  let image = UIImage(data: bytes),
                  (try? bytes.write(to: file(for: entry.id), options: .atomic)) != nil else { continue }
            versions[entry.id] = version
            downloaded[entry.id] = image
            saveVersions()
        }
        return changed
    }

    private func remove(_ id: String) {
        guard versions[id] != nil || downloaded[id] != nil else { return }
        try? FileManager.default.removeItem(at: file(for: id))
        versions[id] = nil
        downloaded[id] = nil
        saveVersions()
    }

    private func file(for id: String) -> URL { folder.appendingPathComponent("\(id).img") }

    private func saveVersions() {
        if let data = try? JSONEncoder().encode(versions) {
            try? data.write(to: folder.appendingPathComponent("versions.json"), options: .atomic)
        }
    }

    /// Ids become file names, so only allow what the server itself allows.
    private static func isSafeID(_ id: String) -> Bool {
        !id.isEmpty && id.count <= 32 && id.allSatisfy { ($0.isLowercase && $0.isASCII) || $0.isNumber || $0 == "-" }
    }
}
