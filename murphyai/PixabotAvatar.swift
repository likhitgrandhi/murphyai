import Foundation
import AppKit
import SwiftUI

// MARK: - Animated GIF renderer

struct AnimatedGifView: NSViewRepresentable {
    let path: String

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        container.wantsLayer = true

        let imageView = NSImageView()
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.animates = true
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.imageAlignment = .alignCenter
        imageView.image = NSImage(contentsOfFile: path)
        // Prevent NSImageView's intrinsic size from inflating the container.
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)

        container.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let imageView = nsView.subviews.first as? NSImageView {
            imageView.image = NSImage(contentsOfFile: path)
            imageView.animates = true
        }
    }
}

/// Deterministic 32×32 pixel-art avatars from pixabots.com.
/// Same name → same numeric ID → same avatar, always.
/// Valid IDs are integers 0–10751 (16 eyes × 8 heads × 7 bodies × 12 tops).
enum PixabotAvatar {
    static func id(for seed: String) -> String {
        let normalized = seed.lowercased().trimmingCharacters(in: .whitespaces)
        var hash: UInt64 = 14695981039346656037 // FNV-1a offset basis
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1099511628211
        }
        // Each position has its own valid range:
        // eyes 0-f (16), heads 0-7 (8), body 0-6 (7), top 0-b (12)
        let eyes  = Int(hash        % 16)
        let heads = Int((hash >> 16) % 8)
        let body  = Int((hash >> 32) % 7)
        let top   = Int((hash >> 48) % 12)
        return String(eyes, radix: 16) + String(heads) + String(body) + String(top, radix: 16)
    }

    static func url(for seed: String, size: Int = 128, animated: Bool = false) -> URL {
        let base = "https://pixabots.com/api/pixabot/\(id(for: seed))?size=\(size)"
        return URL(string: animated ? base + "&animated=true" : base)!
    }

    /// Downloads the PNG (or GIF when animated=true) and writes it to `destination`.
    static func downloadAvatar(for seed: String, to destination: URL, animated: Bool = false) async -> String? {
        let fm = FileManager.default
        try? fm.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        do {
            let (data, response) = try await URLSession.shared.data(from: url(for: seed, animated: animated))
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { return nil }
            guard !data.isEmpty else { return nil }
            try data.write(to: destination, options: .atomic)
            return destination.path
        } catch {
            return nil
        }
    }
}
