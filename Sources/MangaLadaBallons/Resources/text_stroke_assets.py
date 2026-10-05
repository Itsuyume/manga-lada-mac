"""Pinned optional text-segmentation assets, shared by installer and runtime."""
import hashlib
from pathlib import Path

MODEL_ID = "mayocream/koharu-text-sam-ts-l"
MODEL_REVISION = "5dd97423e0fbf2404264979136d47e8101144046"
MODEL_FILE = "model.safetensors"
MODEL_SHA256 = "bcd9525291677f467f0603509a0ca3df35711b4e3417cefce8da6bfc97164f45"
CODE_ID = "ymy-k/Hi-SAM"
CODE_REVISION = "69009434d4dba5541f228d8f5acb0754c333d417"
CODE_HASHES = {
    "hi_sam/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "hi_sam/modeling/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "hi_sam/modeling/build.py": "35fa87b6ff2c1acb10888c369169388f8ef1daa0923a15fccc50c9d62c4e8420",
    "hi_sam/modeling/common.py": "f4963a22a41b5fab2150a406aa0bebe186bdbe282f1e1853e8d4c0fe06d46414",
    "hi_sam/modeling/efficient_hi_sam.py": "7d77f997afd4567e36c97b64fe12888a9f91f7060311f0c5143f3e84ce729fea",
    "hi_sam/modeling/efficient_sam/__init__.py": "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
    "hi_sam/modeling/efficient_sam/efficient_sam_decoder.py": "38ce95469ef98055a948fb9b09456753227c10758c3522436e018f4a96762746",
    "hi_sam/modeling/efficient_sam/efficient_sam_encoder.py": "2e2ef6123d06cf4c4b1dd833364ce737481ac7af301f4366e7e5944811248c94",
    "hi_sam/modeling/efficient_sam/mlp.py": "f6ef4945ef9a0b94ad2a4ff405e81718a7e73fb10423c36a6f69663e0790070a",
    "hi_sam/modeling/efficient_sam/two_way_transformer.py": "bf1e5e1fc5693ca6a56eb89b349f1cb38ca55e38fa7b3a236b140b5738ec2808",
    "hi_sam/modeling/hi_sam.py": "65227d9e72626214b83a1f65e45b7d8f997c03cdbc120eb0a61ebb24b908497c",
    "hi_sam/modeling/image_encoder.py": "0e92f0d3746002f77c5fadeedd61333000dcd0bfaa8556177ed8a8cb844ef5f1",
    "hi_sam/modeling/mask_decoder.py": "5944d78ea73137ddfd4289025cc6de7516b43e4a42e27b7280e7febc63bf78c4",
    "hi_sam/modeling/modal_aligner.py": "0793e92b8772396b665c04a06c7ed2de4300a5adc0cf815c015c3fafd94cac08",
    "hi_sam/modeling/prompt_encoder.py": "eb17b888067467fc0a46800803dfeb2732464e61c01415dc845a8e1762697a54",
    "hi_sam/modeling/transformer.py": "680c463c365bacb9304468f91addc8131d8de8aeb96bfc3e39ebb365f01a29a0",
}
PATCHED_ENCODER_SHA256 = "1d10bc00a980e65b52d5a36fa69cde15f31b2e56f279f0fd408509a15c5019c7"


def verify_text_strokes(root: Path, *, installed: bool = True) -> None:
    expected = CODE_HASHES | {MODEL_FILE: MODEL_SHA256}
    if installed:
        expected["hi_sam/modeling/image_encoder.py"] = PATCHED_ENCODER_SHA256
    for name, digest in expected.items():
        with (root/name).open("rb") as stream:
            actual = hashlib.file_digest(stream, "sha256").hexdigest()
        if actual != digest:
            raise ValueError(f"Text stroke asset checksum mismatch: {name}")


def prepare_text_strokes(root: Path) -> None:
    """Drop inference-only activation checkpoint wrappers; never patch global torch."""
    verify_text_strokes(root, installed=False)
    path = root/"hi_sam/modeling/image_encoder.py"
    source = path.read_text()
    for layer in ("attn", "mlp"):
        original = f"cp.checkpoint(self.{layer}, x)"
        if source.count(original) != 1:
            raise ValueError("Unexpected Hi-SAM checkpoint wrapper")
        source = source.replace(original, f"self.{layer}(x)")
    path.write_text(source)
    verify_text_strokes(root)
