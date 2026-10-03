# Manga translator & Manga Reader

일본어 만화를 한국어로 자동 번역·식자하는 macOS 앱과 별도의 만화 뷰어입니다. 예전 **Manga Lada** 프로젝트를 이어서 개발했습니다.

## 두 앱

- **Manga translator**: 책 전체를 순서대로 처리합니다. 말풍선 검출 → 만화 일본어 OCR → 원문 제거 → 페이지 단위 번역 → 말풍선 윤곽에 맞춘 한국어 식자 → 지정한 폴더에 자동 저장합니다. 원문/번역 전환, 문구 검수·수정, 글꼴·크기 조정, 중단·다시 열어 이어가기, PNG·CBZ 저장을 지원합니다. 시각 모델로 효과음을 추가 인식하는 느린 실험 기능은 설정에서 켭니다.
- **Manga Reader**: 번역 완료 폴더 또는 원문 책을 읽습니다. 한 페이지·두 페이지·연속 스크롤, 일본식 오른쪽→왼쪽 및 반대 방향, 표지 단독 표시, 페이지/너비 맞춤, 확대·축소, 썸네일, 페이지 번호 이동, 책갈피, 마지막 읽은 페이지, 전체화면을 지원합니다. 번역 엔진 없이 사용할 수 있습니다.

두 앱은 읽기 화면과 파일 가져오기 모듈을 공유합니다. 번역기에서 **Reader로 읽기**를 누르면 완성본 폴더가 뷰어에서 열리고, Reader의 **이 책 번역하기**는 원문을 번역기로 전달합니다.

## 사용 방법

1. Manga translator에서 파일 또는 폴더를 엽니다. 상단의 **전체 번역 시작**을 누르거나 **열면 자동 번역**을 켭니다. 자동 번역은 최초 기본값으로 켜져 있으며 변경한 선택을 기억합니다.
2. 처음에는 완성본 저장 폴더를 선택합니다. 책마다 `책이름_한국어/00001.png` 형태로 저장합니다. 원본 파일을 수정하지 않습니다.
3. 진행 중에도 원문·완성 페이지를 볼 수 있습니다. **중단**하면 저장한 페이지와 캐시를 보존합니다. 같은 책을 다시 열어 이어갈 수 있습니다.
4. 놓친 문구는 **영역 지정**을 켜고 원본 위에서 글자와 배치 공간을 드래그한 뒤 **선택 영역 번역**을 누릅니다. 이미지의 **번호·종류**와 오른쪽 검수 창은 서로 연결됩니다. 대사(말풍선)·나레이션·표지 제목·효과음의 색과 개수를 표시하고, 번호를 누르면 해당 검수 항목으로 이동합니다. 여러 말풍선을 드래그하면 선택한 번호를 보여주고 문구와 배치 공간을 각각 유지합니다. 지정한 범위와 문구는 캐시에 보존합니다. 일본어 원문·한국어·종류를 고치고 **수정 적용**을 누르면 저장합니다. **이 문구 다시 번역**은 수정한 원문만 다시 번역합니다. 설정에서 글꼴과 크기를 바꾸면 완료한 페이지 전체에 다시 적용합니다.
5. **저장 → 완성본 CBZ 저장**으로 묶거나 **Reader로 읽기**를 누릅니다.

방향키는 선택한 읽기 방향을 따릅니다. Space/Page Down은 다음 페이지, Page Up은 이전 페이지, Home/End는 처음/마지막 페이지입니다. 번호 입력 후 Return으로 이동합니다. 글자 입력 중에는 페이지 단축키가 작동하지 않습니다.

## 파일 형식

폴더(하위 폴더 포함), ZIP/CBZ, 7z/CB7, RAR/CBR, TAR 및 gzip/bzip2/xz 압축 TAR, PDF, PNG/JPEG/WebP/GIF/TIFF/BMP/HEIC/HEIF/AVIF를 가져옵니다. 파일 열기 창에서 이미지를 열면 같은 폴더의 이미지 전체를 자연스러운 숫자 순서로 읽습니다. 사진 등 외부 앱에서 전달한 이미지와 복사한 이미지(`⌘V` 또는 `⇧⌘V`)는 선택한 한 장만 앱 내부에 복사합니다. 이미지가 클립보드에 있으면 입력란에 초점이 있어도 가져오며 일반 텍스트는 입력란에 그대로 붙입니다. 임시 파일이 사라져도 계속 읽을 수 있고 동일 이미지의 중복 저장을 피합니다. 이미지 데이터 붙여넣기·드롭은 100MB·6,400만 픽셀까지 받으며 사진 보관함 전체를 스캔하지 않습니다. 실제 이미지 디코딩은 macOS ImageIO에 따릅니다. PDF는 읽기·번역용 PNG로 변환합니다.

macOS 내장 libarchive를 사용하므로 7z 프로그램을 따로 설치할 필요가 없습니다. 암호가 있는 압축 파일과 분할 압축은 먼저 해제해야 합니다. 손상·빈 책·안전하지 않은 압축 경로는 오류로 표시합니다. 생성한 번역 폴더는 원본 폴더의 재귀 스캔에서 제외합니다.

## 기본 로컬 모델

기본 번역 모델은 [TranslateGemma 12B](https://ollama.com/library/translategemma)입니다. 약 8.1GB이며 페이지의 일본어 문구를 함께 한국어로 번역합니다. 앞 페이지 문맥 전달은 Qwen/Gemini 모드에서 사용합니다. 장식된 저해상도 표지 제목 OCR과 선택한 효과음 추가 인식은 [Qwen3.5 9B](https://ollama.com/library/qwen3.5)를 사용하며 약 6.6GB입니다. OCR·원문 제거 모델은 책을 처리하는 동안 메모리에 유지하므로 페이지마다 다시 로드하지 않습니다.

설정의 **로컬 모델**에서 TranslateGemma·Qwen을 선택하거나 다른 로컬 모델 이름을 직접 입력할 수 있습니다. 선택한 모델의 처리 방식과 저장 공간을 표시합니다. 모델을 바꾸고 저장한 뒤 **전체 번역 시작**을 눌러 다시 번역합니다. 기존 모델의 번역 캐시는 보존하며 모델별로 구분합니다. Qwen은 문구 종류도 판단하지만 항상 더 정확한 번역을 보장하지 않습니다.

모델을 내려받은 뒤에는 유료 API 키 없이 실행할 수 있습니다. 로컬 모드는 루프백 주소만 허용하며 클라우드 모델 이름을 거부합니다. 두 Ollama 모델과 별도의 OCR·원문 제거 모델을 저장할 공간이 필요합니다.

로컬 모델의 생성 완료 여부와 출력 제한 중단을 확인해, 잘린 문장을 완성된 번역으로 저장하지 않습니다. 한국어 문장에 일본어 한자가 남았거나 문구 종류가 누락된 응답은 검증 오류로 처리하고 한 번만 수정 요청을 보냅니다. 이 검사는 응답 누락을 막는 장치이며 인물 관계·말투·문맥의 의미 정확도를 보장하지 않습니다.

새 Mac의 최초 준비:

```bash
brew install ollama
ollama serve
# 다른 터미널에서
ollama pull translategemma:12b
ollama pull qwen3.5:9b
./scripts/setup_ballons_engine.sh
```

기존 BallonsTranslator 설치가 있으면 그대로 사용합니다. 앱은 설치된 Ollama 명령을 찾아 로컬 서버를 시작할 수 있고, 설정의 **로컬 모델 준비**는 선택한 모델을 내려받습니다. BallonsTranslator 엔진이 없으면 설치가 필요하다는 오류를 표시합니다. 엔진 설치 스크립트는 Python 3.8~3.12를 요구합니다.

## 선택 사항: 저가 API

설정에서 Gemini Flash-Lite를 선택할 수 있습니다. 기본 모델은 `gemini-2.5-flash-lite`이며 사용자가 입력한 키는 macOS 키체인에 저장합니다. OCR·효과음 인식·원문 제거는 로컬에서 수행하고 인식한 텍스트와 앞 페이지 문맥을 Gemini에 전송합니다. 정확한 비용과 무료 할당량은 [Google 공식 가격표](https://ai.google.dev/gemini-api/docs/pricing)를 확인하세요. 자동으로 유료 API에 전환하지 않습니다.

실제 키를 사용하는 Gemini 호출은 기본 검증에서 실행하지 않습니다. HTTP 계약·키 전달·오류 처리만 별도 검증합니다.

## 번역 품질 범위

대사·나레이션은 항상 **가로쓰기·가운데 정렬**입니다. 이미지 폭과 높이에서 추정한 한 페이지 폭에 비례하는 기본 크기를 두고 OCR 글자 크기의 중앙값을 좁은 범위에서 반영합니다. 기본 크기를 100/90/80/70/60/50% 단계로 줄입니다. 최소 크기는 페이지 기준 폭의 1.05%이며 아주 좁은 말풍선에서는 내부 폭의 22%까지 낮추되 10px 미만으로 줄이지 않습니다. 줄 간격은 1.20배, 좌우 여백은 글자 크기의 0.32배이며 좁은 줄에서는 줄 폭의 6%로 제한합니다.

일본어 영역을 기준으로 **원본 이미지의 말풍선 테두리**를 찾고, 밝은 파스텔 말풍선·검은 설명 상자·페이지 끝에 잘린 말풍선까지 줄마다 사용할 내부 폭을 계산합니다. 글자 외곽이나 그림을 말풍선으로 잘못 쓰지 않도록 인식 영역의 내부 포함률과 배경색을 검사합니다. 배경이 어두우면 흰 글자, 밝으면 검은 글자를 사용합니다. 중앙에 가까운 위치에서 단어 단위 줄바꿈을 우선하되 좁아지는 줄에 맞춰 단어를 나눌 수 있으며 한 글자만 남는 단어 분할을 금지합니다. 연속된 말줄임표·감탄 부호는 별도 줄에 둘 수 있습니다. 연결된 말풍선의 각 대사는 공간을 나누고, 한 말풍선 안의 일본어 열은 하나로 합칩니다. 사용자가 지정한 사각형도 실제 윤곽과 교차한 내부에만 배치합니다. 그림 위 문구는 세로 범위를 유지한 가로 영역과 대비되는 외곽선을 사용하고 패널 경계선을 넘지 않도록 제한합니다. 표지 제목과 효과음은 명시적인 별도 종류로 고정된 서체·방향 규칙을 사용합니다.

효과음 보완은 대사를 저장한 뒤 별도의 이미지 복사본에서 처리합니다. 시각 모델의 좌표는 독립 OCR 또는 기존 인식 영역과 대조합니다. 위치가 검증되지 않은 추정은 원문을 유지하고 검수 창에 알립니다. 보완 실패로 완성한 대사 페이지를 잃지 않으며 경고를 캐시에 보존합니다. 인식·그림 복원 버전이 바뀌어도 원본 영역 ID와 좌표가 모두 일치하면 검수한 일본어와 한국어를 함께 보존합니다. 새 OCR의 영역이나 좌표가 바뀌면 오래된 번역을 재사용하지 않습니다.

말풍선 윤곽을 확정할 수 없는 문구는 검출된 원문 영역 안에서 배치합니다. 읽기 가능한 크기로도 들어가지 않으면 해당 문구를 포함한 오류를 표시하며 잘린 번역을 완료로 저장하지 않습니다. 번역 텍스트 캐시는 식자 실패와 별도로 보존하므로 배치를 수정할 때 모델을 다시 호출할 필요가 없습니다.

전체 자동 처리와 편집을 함께 제공합니다. 그림 위에 겹친 손글씨 효과음, 낮은 해상도, 비정형 말풍선은 인식·원문 제거·위치가 틀릴 수 있습니다. 읽기 순서는 영역 위치를 기반으로 한 휴리스틱입니다. 효과음은 3개 공개 글꼴을 재사용하는 12가지 스타일(굵기·기울기·압축·자간·외곽선) 중 전체 또는 문구별 설정을 적용하며 원본의 모든 커스텀 레터링을 복제하지는 않습니다. 원문과 검수 창을 대조해 필요한 문구를 수정하세요.

## 효과음 폰트집

Rendering 리소스의 `sound-effect-styles.json`이 12가지 스타일의 단일 출처입니다. Black Han Sans, Nanum Brush Script, Nanum Myeongjo 3개 글꼴은 [Google Fonts](https://github.com/google/fonts)에서 제공하는 SIL Open Font License 글꼴이며 라이선스를 함께 포함합니다. 총 글꼴 용량은 약 7.6MB입니다. 새 커스텀 TTF 12개를 만든 것이 아니라 3개 글꼴의 조판을 12가지로 구성했습니다. 글꼴은 번역 앱 내부에만 포함하고 Reader에는 복제하지 않으며 Mac 전체에 설치하지 않습니다. 설정의 **폰트집 보기**는 iCloud에 별도로 저장한 오프라인 표본집을 엽니다.

## 저장·호환성

앱 표시 이름은 **Manga translator**로 바뀌었지만 번들 ID `local.mangalada.mac`, Swift 제품/명령 `MangaLada`, `Application Support/Manga Lada` 경로를 유지합니다. 기존 외부 엔진·원본·캐시를 삭제하지 않습니다. 새 처리 버전은 별도의 캐시 키를 사용합니다. Reader ID는 `local.mangareader.mac`입니다.

`translator-config.json`에는 제공자·모델 이름만 저장하며 API 키를 기록하지 않습니다. 모델, 캐시, 작업 로그와 실행 중간 이미지는 저장소에 포함하지 않습니다. 렌더러의 `render` API는 이미지 생성 실패를 호출부에 전달하도록 `throws`로 변경했습니다. 기존 CLI 제품 이름은 유지합니다.

## 개발·검증

두 앱의 페이지 위에서 **트랙패드 두 손가락을 벌리면 확대, 오므리면 축소**합니다. 배율은 40–400%이며 한 번의 제스처가 시작한 배율을 기준으로 움직입니다. 중단되거나 페이지에서 나간 제스처는 종료하고, 배율 숫자를 누르면 100%로 돌아갑니다.

연속 스크롤에서도 확대 후 좌우로 이동해 페이지의 양끝을 볼 수 있습니다. 배율 표시는 반올림하며 40%에서는 축소, 400%에서는 확대 버튼을 비활성화합니다. 버튼과 제스처는 같은 배율 상태를 사용합니다.

앱이 비활성 상태여도 보이는 본창이 있으면 파일·폴더 선택창을 그 창에 연결합니다. 독립된 선택창이 뒤에 숨어 열기를 계속 기다리는 문제를 방지합니다.

말풍선은 OCR 사각형뿐 아니라 **실제 일본어 글자 마스크**가 내부에 들어가는지 확인합니다. 들쭉날쭉한 말풍선도 줄마다 폭을 구하고, 원문에 비해 지나치게 크거나 멀리 떨어진 컷 테두리를 거부해 문장이 얼굴로 옮겨지는 문제를 막습니다. 글자 마스크가 없는 경우에는 원문 사각형의 내부 포함률로 판단합니다.

원문 제거 단계에는 OCR 줄의 좁은 다각형 대신 여유를 둔 전용 범위를 전달합니다. 기존 글자 마스크의 끝이 잘리는 것을 막으며, 이 사각형 자체를 지우는 영역으로 사용하지 않습니다. OCR 좌표와 말풍선 윤곽은 따로 보존합니다.

```bash
python3 scripts/check_architecture.py
swiftlint lint --strict
swift build --explicit-target-dependency-import-check error
swift run MangaLadaCoreChecks
swift run MangaLadaVisionChecks
swift run MangaLadaRenderingChecks
swift run MangaLadaImportChecks
swift run MangaLadaWorkflowChecks --cache-migration
# 완성본 폴더를 실제 CBZ로 내보내고 모든 페이지 바이트·원본 보존 검사
swift run MangaLadaImportChecks --export /path/to/completed-folder /path/to/output.cbz
# 외부 엔진의 Python 환경에서
python scripts/check_balloon_geometry.py
python scripts/check_supplemental_mask.py
# 실제 설치된 Ballons의 마스크 필터와 어댑터 계약 검사 (모델 실행 없음)
python scripts/check_inpaint_contract.py /path/to/BallonsTranslator-dev
# 외부 엔진과 로컬 모델을 준비한 경우 실제 페이지 전체 처리
swift run MangaLadaWorkflowChecks /path/to/japanese-page.png /path/to/result.png
# 실제 지정 영역 OCR·번역·식자·재실행 보존 검사 (정규화 좌표)
swift run MangaLadaWorkflowChecks /path/to/page.png /path/to/manual.png BookTitle --region=0.1,0.2,0.2,0.3
# 원본 보존, 모든 페이지 크기/저장, 실패 기록을 확인하는 책 전체 검사
swift run MangaLadaWorkflowChecks --book /path/to/book.zip /path/to/output-folder
```

모델의 번역 문장과 시간을 비교할 때는 아래 검수를 별도로 실행합니다. 로컬 모델이 준비되어 있어야 하며 OCR·식자·번역 캐시를 거치지 않고 앱의 실제 번역 경로를 호출합니다. 출력 JSON의 일본어·한국어·검토 항목을 직접 대조해야 합니다. 명령의 성공은 응답 형식과 영역 보존을 뜻하며 의미 정확도의 합격을 뜻하지 않습니다. 기존 보고서 파일은 덮어쓰지 않습니다.

```bash
swift run MangaLadaWorkflowChecks --text-benchmark fixtures/translation-quality-ja-ko.json /path/to/new-report.json --model=translategemma:12b
swift run MangaLadaWorkflowChecks --text-benchmark fixtures/translation-quality-extra-ja-ko.json /path/to/new-extra-report.json --model=qwen3.5:9b
```

행동 검증은 빈/텍스트/이미지 클립보드·외부 이미지 격리·임시 파일 소멸·선택 영역의 역방향 드래그/경계/빈 크기/저장·빈 입력·끝 페이지·양면 순서·번호 누락·잘못된 모델 응답·외부 HTTP 실패·이미지 크기·가로 식자·원본 보존·압축 재사용/동시 접근·저장 폴더 격리·CBZ 왕복을 확인합니다. 내부 구현을 mock하지 않으며 네트워크 경계만 대체합니다. CI가 의존 경계·순환·복잡도·빌드·가벼운 행동 검증을 실행합니다. 외부 OCR 모델이 필요한 검증은 로컬에서 별도로 실행합니다.

## 빌드·설치

```bash
./scripts/build_app.sh
./scripts/install_local_app.sh
```

두 앱은 `dist/`에 생성되고 설치 스크립트는 사용자 `Applications`에 설치합니다. 기존 앱은 `dist/backups/`에 복구 가능한 사본으로 보관합니다. 빌드는 동기화 폴더의 리소스 코드 서명 문제를 피하도록 임시 폴더를 사용합니다. `MANGA_LADA_BUILD_ROOT`, `MANGA_LADA_INSTALL_DIR`, `MANGA_LADA_BACKUP_DIR`로 경로를 지정할 수 있습니다.

설치된 기본 SDK의 SwiftUI 매크로가 누락된 환경은 사용 가능한 SDK를 명시합니다. 스크립트는 추가 빌드 인자를 전달합니다.

```bash
./scripts/install_local_app.sh --sdk /path/to/compatible/MacOSX.sdk
```

앱은 로컬 임시 서명으로 묶으며 배포용 Apple 공증은 포함하지 않습니다. 보안 설정을 끄거나 Xcode 사용권을 자동 승인하지 않습니다.

## 엔진과 참고 프로젝트

[BallonsTranslator](https://github.com/dmMaze/BallonsTranslator)의 외부 검출·manga-ocr·LaMa 엔진을 호출합니다. GPL 엔진 소스와 모델을 이 저장소나 앱에 포함하지 않습니다. 보완 마스크·Swift 렌더러·두 앱의 UI는 이 프로젝트의 코드입니다. [manga-image-translator](https://github.com/zyddnys/manga-image-translator)와 [MTL Studio](https://github.com/yucarez/mtl-studio)의 페이지 단위 처리·검수 흐름을 참고했습니다.
