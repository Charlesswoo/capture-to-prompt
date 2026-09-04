// 원본 아트(흰 배경 위 라운드 사각형)를 macOS 아이콘용 1024px PNG로 가공한다.
// 1) 흰 배경을 스캔해 아트 영역(bbox)만 크롭
// 2) 1024 캔버스에 라운드 사각형 클리핑으로 그려 모서리 흰 잔여물 제거
// 사용: swift scripts/make_icon.swift <입력.png> <출력.png>
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 3,
      let src = CGImageSourceCreateWithURL(URL(fileURLWithPath: args[1]) as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
    fputs("사용법: make_icon.swift <입력.png> <출력.png>\n", stderr)
    exit(1)
}

let w = image.width, h = image.height

// 픽셀 읽기용 RGBA 버퍼
var pixels = [UInt8](repeating: 0, count: w * h * 4)
let ctx = CGContext(data: &pixels, width: w, height: h, bitsPerComponent: 8,
                    bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))

// 흰색(또는 투명)이 아닌 픽셀의 bbox 탐색
func isBackground(_ i: Int) -> Bool {
    let r = pixels[i], g = pixels[i+1], b = pixels[i+2], a = pixels[i+3]
    return a < 16 || (r > 245 && g > 245 && b > 245)
}
var minX = w, minY = h, maxX = 0, maxY = 0
for y in 0..<h {
    for x in 0..<w {
        if !isBackground((y * w + x) * 4) {
            if x < minX { minX = x }; if x > maxX { maxX = x }
            if y < minY { minY = y }; if y > maxY { maxY = y }
        }
    }
}
guard minX < maxX, minY < maxY else { fputs("아트 영역을 찾지 못함\n", stderr); exit(1) }

// bbox 크롭 (컨텍스트 y축은 이미 상단 원점 기준으로 그려짐)
let cropRect = CGRect(x: minX, y: minY, width: maxX - minX + 1, height: maxY - minY + 1)
guard let cropped = ctx.makeImage()?.cropping(to: cropRect) else { exit(1) }

// 1024 캔버스에 라운드 사각형 클리핑으로 그리기 (Apple 아이콘 곡률 ≈ 22.37%)
let size = 1024
let out = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                    bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
let radius = CGFloat(size) * 0.2237
let rect = CGRect(x: 0, y: 0, width: size, height: size)
out.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
out.clip()
out.interpolationQuality = .high
out.draw(cropped, in: rect)

guard let final = out.makeImage(),
      let dest = CGImageDestinationCreateWithURL(
        URL(fileURLWithPath: args[2]) as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    exit(1)
}
CGImageDestinationAddImage(dest, final, nil)
CGImageDestinationFinalize(dest)
print("OK \(args[2])")
