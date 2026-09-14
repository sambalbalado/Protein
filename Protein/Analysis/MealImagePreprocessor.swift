import Foundation
import UIKit

@MainActor
public enum MealImagePreprocessor {
    public static let maximumDimension: CGFloat = 1_600
    public static let maximumByteCount = 2_000_000

    public static func prepare(
        _ image: UIImage,
        maximumDimension: CGFloat = maximumDimension,
        maximumByteCount: Int = maximumByteCount
    ) throws -> MealImageRequest {
        guard image.size.width > 0,
              image.size.height > 0,
              maximumDimension > 0,
              maximumByteCount > 0 else {
            throw MealAnalysisError.invalidImage
        }

        var targetSize = scaledSize(for: image.size, maximumDimension: maximumDimension)
        for _ in 0..<6 {
            let normalized = render(image, at: targetSize)
            for quality in [0.82, 0.68, 0.54, 0.4, 0.28] {
                if let data = normalized.jpegData(compressionQuality: quality), data.count <= maximumByteCount {
                    return try MealImageRequest(imageData: data, mimeType: "image/jpeg")
                        .validated(maxByteCount: maximumByteCount)
                }
            }
            targetSize = CGSize(
                width: max(240, floor(targetSize.width * 0.75)),
                height: max(240, floor(targetSize.height * 0.75))
            )
        }
        throw MealAnalysisError.invalidImage
    }

    private static func scaledSize(for source: CGSize, maximumDimension: CGFloat) -> CGSize {
        let longestSide = max(source.width, source.height)
        guard longestSide > maximumDimension else { return source }
        let scale = maximumDimension / longestSide
        return CGSize(width: floor(source.width * scale), height: floor(source.height * scale))
    }

    private static func render(_ image: UIImage, at size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = true
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }
}
