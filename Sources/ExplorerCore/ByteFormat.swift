import Foundation

public enum ByteFormat {
    private static let units = ["B", "KB", "MB", "GB", "TB", "PB", "EB"]

    /// Compact, deterministic size text: 0 B, 999 B, 1.5 KB, 24 MB, 1.2 GB.
    public static func string(_ bytes: Int64?) -> String {
        guard let bytes, bytes >= 0 else { return "—" }
        if bytes == 0 { return "0 B" }
        if bytes < 1000 { return "\(bytes) B" }

        var value = Double(bytes)
        var unit = 0
        while value >= 1000 && unit < units.count - 1 {
            value /= 1000
            unit += 1
        }
        let decimals = value < 10 ? 1 : 0
        return String(format: "%.\(decimals)f %@", value, units[unit])
    }

    public static func exact(_ bytes: Int64) -> String {
        let number = NumberFormatter.localizedString(from: NSNumber(value: bytes), number: .decimal)
        return "\(number) bytes"
    }
}
