# AGENTS.md

일본어→한국어 Manga translator와 독립 Manga Reader 프로젝트입니다.

## 모듈과 의존 방향

- `MangaLadaCore`: 공용 모델·TextBox·캐시·번역 제공자·읽기 순서·페이지 탐색·압축/이미지 스캔·취소 가능한 프로세스. UI/렌더링/Vision을 가져오지 않습니다.
- `MangaLadaImport` → Core: 폴더·압축·PDF를 ComicBook으로 가져오고 CBZ로 내보냅니다. 파일 작업은 loader actor가 담당합니다.
- `MangaLadaVision` → Core: macOS OCR 경계.
- `MangaLadaBallons` → Core: 외부 Python 엔진과 보완 LaMa 경계. 자체 Python 어댑터만 리소스로 포함합니다.
- `MangaLadaRendering` → Core: 원문 제거 이미지에 한국어·효과음을 렌더링합니다. 이미지 픽셀 크기를 보존합니다.
- `MangaLadaWorkflow` → Core/Ballons/Vision/Rendering: 인식·번역·캐시·식자, 책별 출력 저장. UI 상태와 탐색은 소유하지 않습니다.
- `MangaLadaViewerUI` → Core: 두 앱이 공유하는 읽기 설정·캔버스·썸네일·키보드·파일 열기 UI.
- `MangaLadaApp` → Core/Import/Rendering/Workflow/ViewerUI: 번역 앱의 표시 상태·설정·작업 수명 관리.
- `MangaReaderApp` → Core/Import/ViewerUI: AI 엔진에 의존하지 않는 뷰어.

새 함수·타입을 만들기 전에 기존 모듈을 검색하고 SSOT를 유지합니다. 숨은 re-export, 전역 초기화 순서 계약, 모듈 간 순환을 만들지 않습니다. 구조 검사는 `scripts/check_architecture.py`와 SwiftPM의 explicit import 검사로 강제합니다.

본문 식자 규칙의 SSOT는 `DialogueTypesettingRules`입니다. 대사·나레이션은 가로쓰기와 가운데 정렬을 유지하며 말풍선별로 임의의 세로쓰기를 선택하지 않습니다. `BalloonShape`는 원본 픽셀 좌표를 정규화한 공용 윤곽 모델입니다. 줄 폭 계산·줄바꿈과 폰트 규칙은 Rendering에만 둡니다. 한 글자짜리 단어 조각과 테두리 밖 식자를 금지하며 표지 제목과 효과음만 별도 명시적 규칙을 사용합니다.

원본 윤곽과 배경색을 기준으로 말풍선 내부·글자 대비를 결정합니다. 원문 제거 이미지에서 테두리를 재추정하지 않습니다. 윤곽 안의 글자 포함률을 검사하고 드래그 영역도 윤곽과 교차시킵니다. 캐시 버전과 이전 인식 키의 SSOT는 `JapanesePageKeys`, 이미지와 검수 목록의 종류·색 표시는 `MangaTextKind+Presentation`입니다. 처리 버전 갱신 후 수동 영역·종류 변경·검수 문구 보존을 확인합니다.

효과음 인식 표기와 한국어 기본형은 Core의 `Resources/sound-effect-lexicon.json`이 단일 출처입니다. Core는 목록을 검증하고, Ballons 요청은 검증된 원문 목록을 Python에 명시적으로 전달합니다. Python에 같은 단어 목록을 복제하지 않습니다. 한국어 기본형이 없는 항목은 문맥에 따라 번역을 유지하며 새 모델 응답의 효과음에만 보정을 적용합니다. 기존 검수 캐시를 사전으로 일괄 덮어쓰지 않습니다.

정규화 사각형의 면적·교차·합집합은 Core의 `TextBoxGeometry`를 재사용합니다. `JapaneseHorizontalOCR`는 두 OCR의 영역을 대조해 가로 원문만 보완하며 좌표·윤곽·번호를 변경하지 않습니다. 플랫폼 OCR 호출은 Workflow→Vision 경계에 두고, 세로 글자·수동 검수·중복 또는 부분 인식은 보완 대상으로 삼지 않습니다.

효과음 보완 경계는 Ballons의 `optical_effects.py`입니다. 새 영역은 실제 macOS OCR 후보와 해당 위치의 만화 OCR 원문이 일치할 때만 추가합니다. 기존 영역의 글자 제거 범위 보완은 저장 좌표·번호를 바꾸지 않습니다. 글자 마스크는 `erase_supplemental_text.glyph_mask`를 재사용하며 단색 복원도 검증된 마스크 안에만 적용합니다. 두 OCR의 불일치·수동 검수·다중 영역 충돌은 자동 추가 대상에서 제외합니다. 새 효과음이 추가돼도 기존 영역의 검수 문구는 유지합니다. Python 내부 의존 방향과 순환도 구조 검사에서 강제합니다.

## 구현·오류 처리

Strict Swift 6를 유지합니다. 강제 캐스팅·임의 Any 계약을 추가하지 않습니다. Foundation/AppKit의 필수 외부 계약은 해당 어댑터에서만 처리합니다. 모델 응답의 누락·중복·빈 번역·잘못된 좌표·HTTP 오류를 명시적으로 거부합니다. 번역/API 실패를 다른 제공자나 원문으로 조용히 대체하지 않습니다. 취소는 실패 페이지로 기록하지 않습니다.

함수 본문 90줄, 파일 450줄, 복잡도 12, 함수 중첩 3단계 상한은 `.swiftlint.yml`이 관리합니다. 긴 UI나 처리 흐름은 책임별 파일로 나눕니다. 외부 리소스 정리와 사용자 취소 이외의 오류를 빈 catch/try?로 숨기지 않습니다.

## 파일·호환성·게시

원본과 사용자의 기존 변경을 보존합니다. 출력은 사용자가 지정한 별도 폴더에 책별로 저장하고 기존 무관한 폴더를 덮어쓰지 않습니다. 앱 이름을 바꾸어도 기존 CLI 제품·번들 ID·Application Support 경로는 README의 호환성 계획을 따릅니다. 외부 Ballons 소스/모델은 vendoring하지 않습니다.

공개 저장소에 키·토큰·.env·사용자 절대 경로·원본 만화·개인 데이터·캐시·모델·앱 바이너리를 추가하지 않습니다. 변경 전후 Git 상태를 확인합니다.

## 검증

README의 검증 명령을 실행합니다. 빈 입력, 끝 페이지, 동시 접근, 실패 경로와 파일 부작용부터 확인합니다. 테스트는 출력·상태·원본 보존을 확인하며 내부 구현을 mock하지 않습니다. HTTP 대체는 외부 네트워크 경계에만 둡니다. 실제 모델을 실행하지 않은 결과는 완료로 말하지 않습니다.

화면 변경은 실제 내용으로 HTML을 설계해 브라우저에서 확인하고, 설치한 네이티브 앱에서도 크기·겹침·키보드·탐색·저장을 확인합니다. 빌드 성공과 화면/번역 품질 검수를 구분합니다.
