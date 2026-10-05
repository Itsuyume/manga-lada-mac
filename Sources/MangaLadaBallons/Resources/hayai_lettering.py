"""Optional local model boundary for the recognition-only lettering harness."""
import hashlib
import json
from pathlib import Path
import cv2
import numpy as np

MODEL_ID = "JustANormalTinkerer/hayai-ocr-v2.5-nova"
MODEL_REVISION = "e34d7755ed11e626c5ba39544af5d66f20ee57cc"
VISION_ID = "google/siglip2-base-patch16-naflex"
VISION_REVISION = "b53b807d3a2d5e2b3911292f2d69e5341cdc064c"
VISION_HASHES = {
    "config.json": "c0b8c2e7f0527b0bea1b1d9abe0381c0f294352df92439c54590b8420e539118",
    "preprocessor_config.json": "1125703e5446d5b6ff4d5893a33bac128cdd21dc12e3dad2469a648fb0ae3bf7",
}
MODEL_HASHES = {
    "model.safetensors": "ac63cd177c5b68bd91e18dd4408e0400461c7cf19f484b0da1643e232d1ffc3a",
    "modeling_hayai.py": "a6be06426c77db2f521928a792a057d13ab17fe477b4df6f1b88861b2fc4da36",
    "configuration_hayai.py": "47abd38cf1bae7aef27d01f5b8b4aa0960a7bc625a8afad79c4762ff5e5ed970",
    "config.json": "880c99360c77733032fe06e94de8123dca21610cab782c6df43e4e26c9d37c41",
    "tokenizer.json": "f8a0a909c628a684fe463094614e236a8b1d3609e7770f77e7beafaf1056bf13",
    "tokenizer_config.json": "6fb6c69afaedf1275872d3e62e276fd4467bd00da7a84cbbb5566a2cd28f58f6",
}
REMOTE_CONFIG = 'Siglip2VisionConfig.from_pretrained("google/siglip2-base-patch16-naflex")'
LOCAL_CONFIG = 'Siglip2VisionConfig(**config.vision_config)'
LOCAL_HASHES = MODEL_HASHES | {
    "modeling_hayai.py": "d2b18f0c4ec9000017199b239b4229590c36a6f46002d532d6c317bdb34a5af3",
    "config.json": "f10c52a704b46089b260d8c5a4639ba99d1bdbfaaffc4ae3596fc983bdea11be",
}


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024*1024), b""):
            value.update(chunk)
    return value.hexdigest()


def verify_snapshot(path: Path) -> None:
    for name, expected in MODEL_HASHES.items():
        if digest(path/name) != expected:
            raise ValueError(f"Lettering model checksum mismatch: {name}")


def prepare_local_model(model: Path, processor: Path) -> None:
    """Installer boundary: verify upstream code, then remove its implicit Hub fetch."""
    verify_snapshot(model)
    for name, expected in VISION_HASHES.items():
        if digest(processor/name) != expected:
            raise ValueError(f"Vision configuration checksum mismatch: {name}")
    code_path = model/"modeling_hayai.py"
    code = code_path.read_text()
    if code.count(REMOTE_CONFIG) != 1:
        raise ValueError("Unexpected Hayai vision configuration hook")
    config = json.loads((model/"config.json").read_text())
    vision_config = json.loads((processor/"config.json").read_text())
    config["vision_config"] = vision_config.get("vision_config", vision_config)
    code_path.write_text(code.replace(REMOTE_CONFIG, LOCAL_CONFIG))
    (model/"config.json").write_text(json.dumps(config))
    manifest = dict(model=MODEL_ID, revision=MODEL_REVISION, visionRevision=VISION_REVISION,
                    files={f"model/{name}": digest(model/name) for name in MODEL_HASHES})
    manifest["files"]["processor/preprocessor_config.json"] = digest(processor/"preprocessor_config.json")
    (model.parent/"manifest.json").write_text(json.dumps(manifest, indent=2))


def verify_installation(root: Path) -> dict:
    manifest = json.loads((root/"manifest.json").read_text())
    if manifest["model"] != MODEL_ID or manifest["revision"] != MODEL_REVISION or manifest["visionRevision"] != VISION_REVISION:
        raise ValueError("Unsupported lettering model revision")
    required = {f"model/{name}": value for name, value in LOCAL_HASHES.items()}
    required["processor/preprocessor_config.json"] = VISION_HASHES["preprocessor_config.json"]
    if manifest["files"] != required:
        raise ValueError("Lettering model manifest differs from the pinned files and hashes")
    for name, expected in manifest["files"].items():
        if digest(root/name) != expected:
            raise ValueError(f"Installed lettering model was modified: {name}")
    return manifest


class HayaiLetteringOCR:
    """One explicitly selected device, no runtime downloads or model fallback."""
    def __init__(self, root: Path, device: str = "mps"):
        self.manifest = verify_installation(root)
        import torch
        from transformers import AutoModel, PreTrainedTokenizerFast, Siglip2ImageProcessor
        if device not in ("mps", "cpu") or (device == "mps" and not torch.backends.mps.is_available()):
            raise ValueError("Requested lettering OCR device is unavailable")
        self.torch, self.device = torch, device
        self.processor = Siglip2ImageProcessor.from_pretrained(root/"processor", local_files_only=True)
        self.tokenizer = PreTrainedTokenizerFast.from_pretrained(root/"model", local_files_only=True)
        self.model = AutoModel.from_pretrained(root/"model", trust_remote_code=True,
                                              local_files_only=True).to(device).eval()

    def __call__(self, crop: np.ndarray) -> str:
        image = cv2.cvtColor(crop, cv2.COLOR_BGR2RGB)
        inputs = self.processor(images=[image], max_num_patches=512, return_tensors="pt").to(self.device)
        with self.torch.inference_mode():
            texts = self.model.generate(**inputs, tokenizer=self.tokenizer, max_new_tokens=128, repetition_penalty=1.)
        if len(texts) != 1 or not isinstance(texts[0], str):
            raise ValueError("Lettering OCR returned an invalid response")
        return texts[0]
