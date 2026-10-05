# 장식 글자 OCR

앱에서 선택할 수 있는 로컬 OCR과, 전체 번역을 실행하지 않고 일본어 글자만 확인하는 인식 전용 경로입니다. 두 경로는 같은 인식·대조 모듈을 사용합니다. 최초 기본값은 기존 만화 OCR이며 다른 모델로 조용히 대체하지 않습니다.

- 후보 탐색: 닫힌 윤곽·짧게 끊긴 윤곽·우세 배경색과 내부 획을 이용합니다. 큰 연결 글자 하나도 후보로 허용합니다. 기존 엄격한 자동 삭제 경로는 그대로입니다.
- 글자 인식: Hayai OCR v2.5 Nova, 512 패치, 원본 비율 유지. 원본/색 여백 두 크롭을 읽고 불일치하거나 짧은 가나 단위가 3회 이상 반복될 때 극성을 정리한 세 번째 크롭을 읽습니다. 반복 글자는 세 결과가 모두 같아야 확정합니다.
- 결과: `consistent`는 두 전처리의 결과 일치, `needsReview`는 불일치 또는 유효한 일본어 결과 없음, `blank`는 단색 크롭입니다. 일치는 의미 정확도의 보증이나 확률이 아닙니다.
- 가림표·반복·작은 가나를 임의로 치환하지 않습니다. 모든 인식 후보가 보고서에 남습니다.
- 원본·번역 캐시·완성 이미지에 쓰지 않습니다. `scan`은 호출당 후보 최대 8개, 긴 축 최대 1280으로 후보를 탐색합니다. 모든 모드의 OCR 크롭 긴 축은 최대 1600, 크롭당 OCR 호출은 최대 3회입니다.

위 마지막 항목의 읽기 전용 보장은 아래의 `inspect_lettering.py`와 `letteringOnly` 요청에 적용됩니다. 앱의 일반 페이지 처리는 원래대로 번역·완성본을 저장합니다.

## 앱에서 사용

**추가 검출 시험 적용**은 Hayai에 38MB 검출 모델을 더해, 기존 검출기가 놓친 닫힌 말풍선 안의 글자를 최대 8개 보완합니다. 기존 문구와 수동 검수는 제외합니다. 점선·톱니형·어두운 배경 등에서 관측한 내부와 실제 글자 성분을 대조하며, 위치 사각형 전체를 지우지 않습니다. 일반 Hayai 선택에는 추가 모델이 필요하지 않습니다.

이 옵션도 그림과 얽힌 모든 효과음을 자동으로 처리하지는 않습니다. 말풍선 내부를 확인할 수 없거나 글자 일부만 지워지는 후보는 원본에 남깁니다. 검출 전용 도구가 글자를 찾았다는 사실과 앱이 해당 영역을 안전하게 번역·제거했다는 사실을 구분해야 합니다. 전체 제공 이미지의 누락·의미 정확도 검증을 대신하는 옵션이 아닙니다.

모델 설치 후 설정에서 **일본어 글자 인식 → 장식 글자 OCR · Hayai**를 고르고 저장합니다. 자동으로 검출한 글자와 직접 드래그한 영역 모두 이 OCR을 사용합니다. 기존 완성 이미지는 설정만 바꿔도 재처리하지 않으며, 같은 원본을 다시 열어 처리하거나 현재 페이지 재번역을 실행해야 새 인식이 적용됩니다.

인식 결과가 끝까지 일치하지 않은 자동 영역은 **글자 인식 확인 필요 · 원본 유지**로 표시합니다. 해당 영역의 원본 그림을 복원해 저장하고 번역 모델에 전달하지 않습니다. 검수창에서 후보를 고르거나 원문을 수정한 뒤 **이 문구 다시 번역 → 수정 적용**으로 확정할 수 있습니다. 수동 드래그에서 불일치하면 제거·저장 전에 오류를 표시합니다.

새 OCR 캐시는 기존 만화 OCR과 분리됩니다. 첫 이관 때 자동 원문을 다시 읽고 달라진 원문에 이전 번역을 붙이지 않습니다. 직접 수정한 원문·글꼴·배치·원본 유지 선택은 보존합니다. 명시적으로 재번역할 때에도 수정한 일본어 원문은 유지하고 한국어만 새로 요청합니다.

## 설치와 실행

기존 Ballons Python 환경에서 실행합니다. 공개 모델 약 629 MB를 Application Support의 `Manga Lada/LetteringOCR`에 따로 둡니다. 앱이나 Git 저장소에는 모델을 넣지 않습니다. 추가 API/Ollama 요청은 없습니다.

```sh
PYTHON="$HOME/Library/Application Support/Manga Lada/ballons-engine/bin/python"
"$PYTHON" -B scripts/setup_lettering_ocr.py

# 이미 잘라 둔 글자 크롭. 출력은 새 파일을 지정합니다.
HF_HUB_OFFLINE=1 "$PYTHON" -B scripts/inspect_lettering.py crop.png --mode crop --output recognition.json

# 이미지에서 불규칙 말풍선 후보 탐색 후 해당 크롭만 인식합니다.
HF_HUB_OFFLINE=1 "$PYTHON" -B scripts/inspect_lettering.py page.png --mode scan --output candidates.json
```

`--device cpu`로 CPU를 명시적으로 선택할 수 있습니다. 기본은 macOS MPS이며, 사용 불가능한 장치를 조용히 다른 장치로 대체하지 않습니다. 설치 파일이나 해시가 맞지 않으면 오류로 중단합니다. 설치 시 upstream 코드의 암묵적인 설정 다운로드 한 곳을 검증 후 로컬 설정 읽기로 바꿉니다.

기존 JSON-lines Python worker에도 `{"source":"crop.png","letteringOnly":"crop"}` 또는 `"scan"`을 전달할 수 있습니다. 응답의 `lettering` 배열은 `bounds`(원본 픽셀 x1/y1/x2/y2), `status`, `text`, `readings`를 가집니다. `text: null`을 번역문이나 삭제 승인으로 해석하면 안 됩니다.

## 자유형 글자 자동 검출 실험

기존 CTD가 영역을 찾지 못하면 Hayai에도 크롭을 전달하지 못했습니다. `detect`는 이 단계에서 독립적인 YOLO11s ONNX 검출기를 사용하는 읽기 전용 경로입니다. 앱의 `hayai-detected` 시험 옵션은 같은 검출기를 사용하되, 앞서 설명한 닫힌 내부와 글자 획 검사를 통과한 영역만 처리합니다. 기본 OCR 설정에는 적용하지 않습니다. 모델의 `text/effect` 값은 참고 분류이고 효과음 여부를 확정하지 않습니다.

```sh
"$PYTHON" -B scripts/setup_text_detector.py
HF_HUB_OFFLINE=1 "$PYTHON" -B scripts/inspect_lettering.py page.png --mode detect --output detected-ocr.json
"$PYTHON" -B scripts/check_text_detection.py
```

추가 모델은 38MB이며 앱 외부 `Manga Lada/TextDetector`에 설치합니다. OpenCV CPU 검출과 기존 Hayai MPS OCR을 사용하며 추가 API나 Ollama는 필요하지 않습니다. 모델은 **CC-BY-NC-SA-4.0**이므로 비상업적 이용 조건을 확인해야 합니다. 원본 weights·README와 고정 해시를 사용하고 추론 중 다운로드나 다른 모델로 대체하지 않습니다.

검출은 종횡비를 유지한 전체/문맥 여백 두 뷰를 사용하며 큰 이미지는 겹치는 4개 타일을 추가합니다. 모든 뷰는 1024 정사각형으로 메모리와 호출 수를 제한합니다. 타일 내부 경계에서 잘린 단어는 제외하고 중복만 제거하며 이웃 말풍선은 합치지 않습니다. 크롭은 짧은 변의 30%까지 넓히되 이웃 검출 영역까지 거리의 절반에서 멈춥니다. 기본 OCR 예산은 24개, `--limit 0..40`으로 조정하며 초과한 후보도 `deferred`와 좌표로 반환합니다.

worker의 `letteringOnly: "detect"`도 같은 모듈을 사용합니다. 결과에는 실제 읽은 `bounds` 외에 `detectedBounds`, `detectionScore`, `detectionHint`가 있습니다. 점수는 OCR 정확도 확률이 아니며 `consistent`도 전체 페이지의 글자 누락이 없다는 의미가 아닙니다.

2026-10-06 공개 실제 크롭에서 기존 자동 검출 0개였던 `バビュン`을 1개로 찾아 읽었습니다. 손글씨 문장과 일반 연결 말풍선의 두 영역도 읽었습니다. **반복 효과음은 횟수/철자가 불일치해 검수 상태이고, 흰색 가로 문장에서는 일부만 검출했습니다.** 낮은 점수의 배경/문장부호 후보도 남습니다. 검출 사각형만으로 자동 지우기를 승인하지 않으며, 해당 그림 위 효과음은 시험 옵션에서도 원본에 남습니다. 선택 예시의 실행 결과이며 전체 효과음 인식 완료나 일반 정확도 수치가 아닙니다.

## 검증과 한계

```sh
"$PYTHON" -B scripts/check_lettering_ocr.py
"$PYTHON" -B scripts/check_lettering_recovery.py
"$PYTHON" -B scripts/check_balloon_candidates.py
"$PYTHON" -B scripts/check_dotted_balloons.py
python3 scripts/check_architecture.py

# 실제 번들 worker와 설치 모델로 번역 없이 OCR 확인. 출력은 새 파일이어야 합니다.
swift run MangaLadaBallonsChecks --ocr-session hayai crop crop.png crop-report.json
swift run MangaLadaBallonsChecks --ocr-session hayai page page.png page-report.json
swift run MangaLadaBallonsChecks --ocr-session hayai reread page.png cache-reread-report.json
```

빈 크롭·잘못된 타입·모델 오류·반복 횟수 불일치·가나 정규화·가림표 보존·극성·큰 연결 획·배율·좌표·원본 보존을 확인합니다. 모델 대체는 외부 OCR 호출 경계에만 두며 기하/합의 로직은 실제 구현을 검사합니다.

2026-10-05 로컬 MPS에서 공개 실제 글자 크롭 6개로 실행했습니다. 큰 장식 효과음, 손글씨, 긴 세로 글자 등 5개가 두 전처리에서 일치했고, 반복 효과음 1개는 횟수가 달라 `needsReview`로 남았습니다. 선택한 소수의 제작자 공개 예시이며 독립 평가 데이터나 일반적인 정확도 수치가 아닙니다. 원본 전체의 누락률·의미 번역·효과음 식자 품질을 입증하지 않습니다. 열린 윤곽, 사진 배경 위 글자, 검출되지 않은 자유형 글자에는 수동 크롭이 여전히 필요할 수 있습니다.

앱 연결 검증에서는 공개 장식 글자 `バビュン`이 실제 번들 worker의 지정 영역 경로로 읽혔고 반복 효과음은 불일치 후보로 반환됐습니다. 실제 일반 연결 말풍선 조각은 작은/큰 두 영역으로 분리되어 읽혔으며 기존 OCR 기록을 다시 읽어도 ID를 보존했습니다. 같은 장식 글자 크롭을 자동 페이지 검출에 넣으면 영역이 0개여서, **OCR 판독 성공과 위치 자동 검출 성공은 구분해야 합니다.** 모든 효과음을 자동으로 찾는 기능의 완료를 의미하지 않습니다.

## 출처

- [Hayai OCR v2.5 Nova 모델](https://huggingface.co/JustANormalTinkerer/hayai-ocr-v2.5-nova), Apache-2.0, revision `e34d7755ed11e626c5ba39544af5d66f20ee57cc`
- [SigLIP2 NaFlex 설정](https://huggingface.co/google/siglip2-base-patch16-naflex), Apache-2.0, revision `b53b807d3a2d5e2b3911292f2d69e5341cdc064c`
- [Hayai 공개 글자 크롭](https://github.com/NopeNopeGuy/hayai-ocr/tree/master/assets/examples), 비교에만 사용. 만화 이미지 원본은 이 저장소에 포함하지 않습니다.
- [Manga text detector v0](https://huggingface.co/lordtrilink/manga-text-detector-v0), CC-BY-NC-SA-4.0, revision `ba686d01c556d4e7c6f382e5d685c7fe75f5dd49`. 제작자는 효과음 클래스가 별도로 평가되지 않았다고 밝히고 있습니다.
