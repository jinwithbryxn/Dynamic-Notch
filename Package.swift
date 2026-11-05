// swift-tools-version: 5.10
// 제품 이름은 Dynamic Notch다. 패키지·실행 파일 이름은 바꾸지 않는다: 설치된 에이전트 훅(~/.claude/settings.json 등)과
// 알림 스크립트가 "Dynamic Notch.app/Contents/MacOS/DynamicNotch" 경로로 이 실행 파일을 부른다.
// The product is Dynamic Notch. The package and executable keep their name because installed agent hooks
// and notification scripts call "Dynamic Notch.app/Contents/MacOS/DynamicNotch".
import PackageDescription

let package = Package(
    name: "DynamicNotch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "DynamicNotch",
            path: "Sources/DynamicNotch"
        )
    ]
)
