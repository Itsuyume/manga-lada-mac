# Manga Lada Mac

MacBook에서 일본 만화 이미지를 열고 스페이스바로 OCR/번역을 실행하는 macOS 네이티브 앱입니다.

## 현재 목표

- 이미지, ZIP/CBZ 또는 폴더 열기
- 방향키로 페이지 이동
- 스페이스바로 일본어 OCR과 한국어 번역 실행
- BallonsTranslator 엔진이 있으면 텍스트 검출, OCR, 번역, 원문 제거를 실행
- 번역기는 앱 상단 메뉴에서 Ballons Google, Google, DeepL, Papago, LLM, Ollama 중 선택
- 원문 제거 이미지 위에 Swift 렌더러가 한국어 문장을 박스 안에 맞춰 다시 식자
- 엔진이 없으면 macOS Vision 기반 내장 OCR로 fallback
- 번역 결과를 실제 PNG 이미지로 저장
- 결과를 로컬 캐시에 저장
- `.app` 번들로 실행

## 기술 선택

- UI: SwiftUI
- 고품질 번역 엔진: [dmMaze/BallonsTranslator](https://github.com/dmMaze/BallonsTranslator)를 외부 Python 엔진으로 실행
- fallback OCR: macOS Vision framework
- 번역: Ballons 내장 Google 또는 Swift provider(DeepL/Papago/OpenAI 호환 LLM/Ollama)
- 캐시: `Application Support/Manga Lada/Cache`
- Ballons/Swift 합성 결과: `Application Support/Manga Lada/BallonsRuns`
- ZIP/CBZ: `Application Support/Manga Lada/Archives`에 자동 압축 해제
- 내보내기: 원문 영역을 불투명하게 지운 뒤 번역 말풍선을 그린 PNG 저장

## BallonsTranslator 엔진 설치

고품질 세로 만화 번역은 BallonsTranslator 엔진을 설치해야 제대로 동작합니다. 스크립트는 `~/Downloads/BallonsTranslator-dev.zip`이 있으면 그 파일을 사용하고, 없으면 GitHub `dev` 브랜치를 clone합니다.

```bash
./scripts/setup_ballons_engine.sh
```

첫 번역에서는 text detector, manga OCR, LaMa inpaint 모델을 내려받기 때문에 시간이 걸릴 수 있습니다. BallonsTranslator는 GPL-3.0 계열 프로젝트라서, 현재 앱은 해당 소스를 번들에 포함하지 않고 사용자 로컬의 외부 엔진으로 호출합니다.

## 로컬 번역기 설정

상단 번역기 메뉴에서 `DeepL`, `Papago`, `LLM`, `Ollama`를 선택할 수 있습니다. API 키는 앱이나 저장소에 넣지 않고 아래 로컬 파일에만 둡니다.

```text
~/Library/Application Support/Manga Lada/translator.local.json
```

예시:

```json
{
  "provider": "ollama",
  "maxConcurrentRequests": 4,
  "deepl": {
    "apiKey": "DEEPL_API_KEY",
    "endpoint": "https://api-free.deepl.com/v2/translate",
    "context": "Japanese manga dialogue translated naturally into Korean"
  },
  "papago": {
    "clientId": "NAVER_CLIENT_ID",
    "clientSecret": "NAVER_CLIENT_SECRET"
  },
  "llm": {
    "apiKey": "OPENAI_OR_COMPATIBLE_API_KEY",
    "endpoint": "https://api.openai.com/v1/chat/completions",
    "model": "gpt-4o-mini"
  },
  "ollama": {
    "endpoint": "http://127.0.0.1:11434/api/chat",
    "model": "gemma3:4b"
  }
}
```

`provider`는 기본 선택값이고, 앱에서 메뉴로 다시 바꿀 수 있습니다. `LLM`은 OpenAI 호환 `/chat/completions` 서버를, `Ollama`는 로컬 Ollama `/api/chat` 서버를 사용합니다. `DeepL`은 여러 텍스트 블록을 한 요청으로 묶고, 나머지 Swift provider는 `maxConcurrentRequests` 값만큼 병렬 번역합니다.

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

Ballons 엔진까지 포함해 실제 만화 페이지를 확인하려면 `./scripts/setup_ballons_engine.sh`를 먼저 실행한 뒤 다음처럼 이미지 경로를 넘깁니다.

```bash
swift run MangaLadaBallonsChecks /path/to/manga-page.png
swift run MangaLadaBallonsChecks --ocr-only /path/to/manga-page.png
```

앱에서는 페이지를 열고 스페이스바를 누르면 같은 엔진 경로를 사용합니다.

빌드된 앱은 `dist/Manga Lada.app`에 생성됩니다.

## 내 Mac에 설치

```bash
./scripts/install_local_app.sh
open "$HOME/Applications/Manga Lada.app"
```
