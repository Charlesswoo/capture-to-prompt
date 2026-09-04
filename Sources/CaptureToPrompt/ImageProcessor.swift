import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// 이미지 전처리: 포맷 판별 + 장변 다운스케일 후 JPEG 재인코딩.
/// 큰 이미지를 그대로 보내면 토큰 비용이 커지므로 장변 1568px로 제한한다.
enum ImageProcessor {
    static let maxDimension: CGFloat = 1568

    /// API에 보낼 (데이터, media_type) 쌍으로 정규화한다.
    /// 이미 작으면 원본 유지(포맷이 지원되는 경우), 크면 JPEG로 다운스케일.
    static func normalize(_ data: Data) -> (data: Data, mediaType: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? CGFloat,
              let height = props[kCGImagePropertyPixelHeight] as? CGFloat else {
            return nil
        }

        let originalType = CGImageSourceGetType(source) as String?
        let supported = ["public.png": "image/png", "public.jpeg": "image/jpeg",
                         "org.webmproject.webp": "image/webp", "com.compuserve.gif": "image/gif"]

        if max(width, height) <= maxDimension,
           let type = originalType, let mediaType = supported[type] {
            return (data, mediaType)
        }

        // 다운스케일 (또는 미지원 포맷 → JPEG 변환)
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimension,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
            return nil
        }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (out as Data, "image/jpeg")
    }
}
