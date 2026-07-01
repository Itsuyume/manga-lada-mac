# Manga Lada Mac

MacBook에서 일본 만화 이미지를 열고 스페이스바로 OCR/번역을 실행하는 macOS 네이티브 앱입니다.

## 현재 목표

- 이미지, ZIP/CBZ 또는 폴더 열기
- 방향키로 페이지 이동
- 스페이스바로 일본어 OCR과 한국어 번역 실행
- 이미지 위에 번역 오버레이 표시
- 번역 결과를 실제 PNG 이미지로 저장
- 결과를 로컬 캐시에 저장
- `.app` 번들로 실행

## 기술 선택

- UI: SwiftUI
- OCR: macOS Vision framework
- 번역: Google Translate 호환 HTTP 엔드포인트
- 캐시: `Application Support/Manga Lada/Cache`
- ZIP/CBZ: `Application Support/Manga Lada/Archives`에 자동 압축 해제
- 내보내기: 원본 이미지 위에 번역 말풍선을 그린 PNG 저장

## 개발 실행

```bash
swift run MangaLada
```

## 검증

```bash
swift run MangaLadaCoreChecks
swift run MangaLadaVisionChecks
swift run MangaLadaRenderingChecks
swift build
./scripts/build_app.sh
```

빌드된 앱은 `dist/Manga Lada.app`에 생성됩니다.

## 내 Mac에 설치

```bash
./scripts/install_local_app.sh
open "$HOME/Applications/Manga Lada.app"
```
