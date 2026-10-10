# 영어 번역과 원문 제거 검증 — 0.2.47

설정의 **원문 언어 → 영어**로 영어→한국어 번역을 선택합니다. 기존 한국어 글꼴, 연결 말풍선 분리, 자동 식자, 영역 지정, 검수 저장과 원본 유지 기능을 공유합니다. 추가 영어 OCR 모델이나 확산 모델을 설치하지 않습니다.

## 처리 경계

| 단계 | 소유 모듈 | 동작 |
| --- | --- | --- |
| 언어·설정 | Core `LanguageCode`, `LocalTranslatorConfiguration` | 기존 설정은 일본어로 읽고, 영어·일본어만 허용 |
| 글자 인식 | Vision `VisionOCRService` | 영어 인식과 작은 이미지 확대, 원본 정규화 좌표 유지 |
| 문단·말풍선 | Ballons `english_regions` | 줄 정렬·간격·윤곽을 대조하고 그림·프레임을 넘어 묶지 않음 |
| 원문 제거 | 공용 Ballons 복원 모듈 | 확인된 획과 안티앨리어싱을 보완한 뒤 말풍선 외곽 보호 |
| 번역·효과음 | Core `TranslationPipeline`, `EnglishSoundEffects` | 왼쪽→오른쪽 문맥, 19개 기본 효과음과 최대 4회 반복형 |
| 식자·검수 | 기존 Rendering·Workflow | 공용 폰트·방향·크기·이동·원본 유지와 저장 |
| 캐시 | Workflow `JapanesePageKeys` | 언어 분리, 배경 갱신과 번역·검수 키 분리 |

원문 제거는 **측정한 단색 배경 → 얇은 획의 OpenCV Telea 복원 → 나머지 LaMa** 순서입니다. Telea는 이미지 안쪽에 있는 성분 중 최대 안쪽 거리 5픽셀 이하의 구멍만 반경 3픽셀로 처리합니다. 입력과 허용된 마스크 밖 픽셀은 바꾸지 않습니다. 자동 처리와 수동 영역 제거가 같은 복원 함수를 사용합니다.

영어 배경 갱신은 좌표와 원문이 정확히 같은 유일한 이전 OCR 영역의 번호를 유지합니다. 달라진 원문이나 중복 후보에 이전 번호·번역을 임의로 붙이지 않습니다. 일본어도 같은 OCR 정책의 제거 갱신은 기존 원문을 재사용하고 다른 정책으로 바꾸면 다시 인식합니다. 전체 캐시를 삭제하지 않습니다.

## 실제 이미지 검증

2026-10-10, Apple Silicon macOS에서 로컬 번역 모델과 설치한 앱을 사용했습니다. 원본 이미지는 저장 전후 바이트가 같습니다. 아래 이미지는 저장소에 넣지 않고 출처와 해시만 기록합니다.

| 실제 입력 | 결과 | 확인한 범위 |
| --- | --- | --- |
| [xkcd 353, Python](https://xkcd.com/353/), 원본 518×588 | 10개 영역 저장·재실행 통과 | 실제 한국어 PNG, 원문 잔상, 그림·프레임 보존, 영어 드래그 재인식·선택 번역·미선택 영역 보존, 캐시 재사용 |
| [Little Nemo 1905-10-15](https://commons.wikimedia.org/wiki/File:Little_Nemo_1905-10-15.jpg), 실제 인접 패널 크롭 1717×346 | 2개 문구 저장·재실행 통과 | 인식 줄 높이가 다른 같은 말풍선의 결합, 인접 말풍선 분리, 낡은 색상 배경과 외곽 보존 |
| [Little Nemo 1908-07-26](https://commons.wikimedia.org/wiki/File:Little_Nemo_in_Slumberland_(1908-07-26).jpg), 작은 원본 크롭 172×212 | 실패 기록 유지 | 원문 누락과 너무 작은 배치 공간. 확대만으로 읽기 품질을 보장할 수 없음 |

실제 xkcd 원문과 승인 획 마스크를 공용 복원 모듈에 넣었을 때 마스크 밖 변경은 **0픽셀**이고 남은 복원 마스크도 0픽셀이었습니다. 설치 앱에서 다시 생성한 원문 제거 PNG는 이 검사 결과와 전체 픽셀이 같았습니다. 이전 번역 문구를 재사용한 채 새 배경을 저장했습니다. 원문·한국어가 모두 완벽하다는 뜻은 아닙니다. 작은 영문 `IS`의 `15` 오인식, 약어·고유명사와 일부 단어의 번역은 검수가 필요합니다.

설치 앱에서 xkcd를 파일 열기 → 영어 처리 → 자동 저장으로 재검증했습니다. Reader에서는 저장 PNG와 화면을 따로 확인했습니다. 이미 열려 있던 같은 파일을 다시 전달하면 옛 이미지가 유지되는 문제를 재현했고, Reader의 성공적인 책 열기에 이미지 갱신 번호를 연결해 화면과 썸네일을 다시 읽도록 수정했습니다. 설치한 Reader 0.2.46에서 동일한 PNG 경로를 원문으로 교체해 다시 열고, 한국어 저장본을 복원해 다시 열었습니다. 앱을 재시작하지 않고 두 교체 모두 화면에 반영됐으며 최종 저장본의 바이트도 그대로 복원했습니다.

입력 SHA-256:

```text
xkcd 원본: d19588260b4e9521b5d3e880447bf57297910c5a971ac270412a455b70033a9e
Nemo 1905 인접 말풍선 크롭: 440a7bd82b6bb3e7b5dfaa7f00b59c4ed79557009fb37d2ce2d4733951fc95ae
```

## 재현 방법

Ballons의 기존 환경에 numpy·OpenCV와 기존 모델이 필요합니다. OCR 모델·사용자 이미지·설정·캐시는 커밋하지 않습니다.

```sh
python scripts/check_architecture.py
python scripts/check_confirmed_ink.py
python scripts/check_stroke_inpainting.py
python scripts/check_inpaint_mask.py
python scripts/check_english_regions.py
python scripts/check_flat_backgrounds.py
python scripts/check_outline_erasure.py
swiftlint lint --strict
swift run MangaLadaCoreChecks
swift run MangaLadaWorkflowChecks --cache-migration
scripts/check_viewer_images.sh
swift run MangaLadaVisionChecks /path/to/english.png --source=en
swift run MangaLadaWorkflowChecks /path/to/english.png /path/to/korean.png --source=en
```

CI도 소스 모듈과 패키지에 들어간 Python 모듈의 출력 행동을 각각 확인합니다. 복원 검사에서는 빈 입력, 잘못된 타입·크기, 작은 마침표, 밝은·어두운·색상 배경, 넓은 구멍, 이미지 경계, 인접 그림, 입력 버퍼 보존과 남은 마스크를 대조합니다. Viewer 검사는 같은 경로의 PNG를 교체한 뒤 실제 새 픽셀을 읽는지도 확인합니다.

## 남은 범위와 확산 모델 검토

복잡한 영문 손글씨·배경 위 효과음의 위치 검출과 모든 영어 효과음의 뜻을 검증하지 않았습니다. 19개 기본 효과음은 실제 목록·반복형·일반 대사 오분류 방지 검사를 통과했으며, 전체 만화의 누락 없는 인식을 보장하지 않습니다. 영어의 가림표 문맥에는 일본어 전용 Qwen 경로를 적용하지 않습니다.

2026-10-10에 SD1.5 인페인팅과 LCM LoRA를 MPS에서 실제 실행했습니다. 같은 승인 마스크를 사용한 512px 비교에서 기존 방식이 더 빠르고 메모리 할당이 적었으며 선화 오차도 작았습니다. 시험한 LCM은 글자 형태를 재생성하는 사례가 있어 앱에 추가하지 않고 시험 모델·별도 환경을 폐기했습니다. [측정 조건·결과·한계](text-erasure-evaluation.md)를 참고하세요. 모델 점수나 확장한 입력 문맥을 새 그림 영역의 제거 권한으로 취급하지 않습니다.
