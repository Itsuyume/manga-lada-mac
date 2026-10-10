# 원문 제거 수정과 LCM 비교 — 0.2.47

## 실제 입력에서 확인한 문제

사용자가 제공한 일본어 흑백 페이지 684×1080과 영어 대사·색상 배경만 포함한 크롭 765×805를 production worker로 처리했습니다. 번역 모델은 호출하지 않았고, 저장된 원문 제거 이미지와 승인 마스크를 원본 픽셀에 대조했습니다. 개인 원본·OCR 문구·검수 파일은 저장소에 포함하지 않습니다.

- 중간 밝기의 종이에서 절대 밝기 127로 획의 극성을 판단해 검은 글씨를 놓쳤습니다. Otsu 분할값과 관측한 종이 밝기를 비교하는 공용 함수를 사용합니다.
- 말풍선 내부 글자 구멍과 OCR 영역에 거의 전부 들어간 문자 성분을 외곽으로 오인해 획을 보호했습니다. 실제 외곽의 관측 성분과 내부 문자를 구분합니다.
- LaMa의 외부 경계 필터가 OCR 사각형 밖의 후리가나를 잘랐습니다. 승인 마스크에서 작업 창을 만들고 작은 획에도 주변 배경을 제공합니다.
- JPEG 흰 종이의 압축 잡음을 질감으로 처리해 잔상을 재생성했습니다. 충분한 밝은 표본을 확인한 글자 성분 주변에서만 단색 복원을 허용합니다.

일본어 9영역과 영어 9문단 영역 모두 저장 이미지의 승인 마스크 밖 변경은 **0픽셀**이었습니다. 실제 일본어 글씨·후리가나와 영어 검은 글씨 제거를 눈으로 확인했습니다. 영어 질감에는 옅은 복원 자국이 남습니다. 원본 배경의 정답을 알 수 없으므로 완전한 복원 점수나 전체 OCR 성공률로 해석하지 않습니다. 원래 검출되지 않은 작은 효과음도 이 제거 검사에서 인식됐다고 주장하지 않습니다.

모델 입력 문맥은 주변 3픽셀을 추가로 가리지만 결과는 최초 승인 마스크 안에만 합성합니다. 작업 창의 64픽셀 주변 여백은 그림 제거 허용 범위가 아닙니다. 제거 이미지 키만 일본어 ink-v5, 영어 ink-v3으로 갱신하고 번역·검수 키와 같은 정책의 기존 인식은 유지합니다.

## LCM 결정: 기존 OpenCV + LaMa 유지

Apple M5 Pro / 64GB에서 기존 방식과 공식 SD1.5 inpainting + LCM LoRA를 실제 실행했습니다. 모든 방식에 동일한 승인 마스크를 입력하고 최종 합성도 그 안으로 제한했습니다.

| 관측값 | 기존 방식 | 시험한 LCM 구성 |
| --- | ---: | ---: |
| 512px 처리, 준비 이후 | 0.013–0.129초 | 4단계 2.09–2.42초 / 8단계 3.67–3.74초 |
| MPS driver 최고 할당량 | 약 1.42GB | 약 9.29GB |
| 정답 선화의 MAE, 작을수록 좋음 | 38.48 | 49.26–57.66 |
| 정답 선화의 edge F1, 클수록 좋음 | 0.305 | 0.212–0.272 |
| 실제 흰 말풍선 | 글씨 제거 | 글자 형태 유지·재생성 발생 |

512×512 네 영역은 실제 흰 말풍선, 오래된 종이의 실제 대사, 원본 정답에 시험 글자를 얹은 선화·종이 대조군입니다. 오래된 대사의 마스크가 일부 글자를 놓쳐 이 사례를 OCR 성공률로 사용하지 않았습니다. 오차 수치는 정답이 있는 선화 대조군에서만 산출했습니다. 기본 모델 검사를 유지했으며 12회 중 5회 사용 불가 결과에는 품질 점수를 부여하지 않았습니다.

LCM 조건: FP16, MPS, LCMScheduler, guidance 4, strength 1, 4/8단계; 정답 대조군 seed 17/29. Diffusers 0.39.0, PEFT 0.21.2, Accelerate 1.15.0, Transformers 4.57.6. SD1.5 inpainting revision `8a4288a76071f7280aedbdb3253bdb9e9d5d84bb`, LCM LoRA revision `cf2fced511dbe7e26c8d1d397e728fbab875db4b`. Safetensors 파일의 해시를 대조했습니다. 모델 준비 시간은 표에 제외했고 최초 로딩은 기존 0.36초, LCM 5.02초였습니다. 첫 LCM 추론은 준비 비용으로 11.96초였습니다. MPS 할당량은 전체 시스템 메모리가 아니며 RSS와 합산하지 않습니다.

평가한 LCM은 속도·메모리·선화 보존에서 이점이 없어 앱에 추가하지 않았습니다. 시험 모델과 별도 환경 약 3.62GB는 복구 가능한 휴지통으로 옮겼습니다. 비교 코드·버전·해시·원시 로그·PNG는 로컬 검증 산출물에 남겼습니다. 다른 LCM 구성 전체에 대한 보편적 결론은 아닙니다.

## 재현 가능한 경계 검사

```sh
python scripts/check_confirmed_ink.py
python scripts/check_outline_erasure.py
python scripts/check_flat_backgrounds.py
python scripts/check_stroke_inpainting.py
python scripts/check_inpaint_mask.py
python scripts/check_architecture.py
swift run MangaLadaWorkflowChecks --cache-migration
scripts/check_packaged_resources.sh "/path/to/Manga translator.app"
```

실제 입력 검증은 설치된 엔진과 패키지 안의 worker를 사용해야 합니다. 단위 픽셀 검사만으로 실제 페이지의 제거 품질을 선언하지 않습니다.

## 모델 출처

- [LCM LoRA 공식 모델](https://huggingface.co/latent-consistency/lcm-lora-sdv1-5)
- [Diffusers LCM 사용 문서](https://huggingface.co/docs/diffusers/en/using-diffusers/inference_with_lcm_lora)
- [SD1.5 inpainting 모델](https://huggingface.co/stable-diffusion-v1-5/stable-diffusion-inpainting)
- [Diffusers Apple Silicon 실행 문서](https://huggingface.co/docs/diffusers/en/optimization/mps)
