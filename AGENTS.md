# AGENTS.md

이 프로젝트는 macOS용 일본 만화 이미지 번역 뷰어입니다.

## 경계

- `Sources/MangaLadaCore`: SwiftUI/AppKit/Vision에 의존하지 않는 모델, 캐시, 번역, 파일 스캔 로직.
- `Sources/MangaLadaVision`: macOS Vision OCR 어댑터. Core에는 의존하지만 UI에는 의존하지 않음.
- `Sources/MangaLadaApp`: macOS UI, 파일 선택, 단축키 처리.
- `scripts`: 빌드와 검증 자동화.

Core에서 App을 import하지 않습니다. Vision OCR은 OS 경계라 App 계층에만 둡니다.

## 개발 원칙

- 새 helper나 shape를 만들기 전에 `MangaLadaCore`의 기존 타입을 먼저 확인합니다.
- 에러는 조용히 삼키지 않습니다. UI 경계에서 사용자에게 보여줄 메시지로 변환합니다.
- 내부 구현을 mock하지 말고, Core 테스트는 실제 출력/상태 변화를 검증합니다.
- 함수가 길어지면 guard clause와 작은 private 함수로 나눕니다.
- `as!`, `as?` 남발과 `Any` 기반 계약을 피합니다.

## 검증

가벼운 검증:

```bash
swift run MangaLadaCoreChecks
swift run MangaLadaVisionChecks
swift build
```

앱 번들 생성:

```bash
./scripts/build_app.sh
```

사용자 Applications 설치:

```bash
./scripts/install_local_app.sh
```
