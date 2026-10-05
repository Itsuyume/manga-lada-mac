"""Optional manga-specific stroke model; erasure approval stays in lettering_strokes."""
import importlib
import importlib.util
from pathlib import Path
import sys
from types import SimpleNamespace
import cv2
import numpy as np
from PIL import Image
from lettering_strokes import stroke_contrast
from text_region_geometry import validate_bgr_image
from text_stroke_assets import MODEL_FILE, verify_text_strokes

IMAGE_SIZE = 1024


def prepare_text_image(image: np.ndarray, *, native: bool) -> tuple[np.ndarray, tuple[int, int]]:
    validate_bgr_image(image)
    height, width = image.shape[:2]
    scale = IMAGE_SIZE / max(height, width)
    if native:
        scale = min(1., scale)
    size = (max(1, round(width * scale)), max(1, round(height * scale)))
    rgb = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
    resized = np.asarray(rgb.resize(size, Image.Resampling.BILINEAR))
    canvas = np.full((IMAGE_SIZE, IMAGE_SIZE, 3), 128, np.uint8)
    canvas[:size[1], :size[0]] = resized
    return canvas, size


def text_stroke_core(image: np.ndarray, mask: np.ndarray) -> np.ndarray:
    """Keep observed dark cores within model evidence, never synthesize missing strokes."""
    normalized = stroke_contrast(image)
    if mask.dtype != np.uint8 or mask.shape != image.shape[:2] or not np.isin(mask, (0, 255)).all():
        raise ValueError("Text stroke model returned an invalid mask")
    selected = mask > 0
    amount = np.count_nonzero(selected)
    gray = cv2.cvtColor(normalized, cv2.COLOR_BGR2GRAY)
    core = selected & (gray < 100)
    if amount > mask.size * .45 or np.count_nonzero(core) < max(16, amount * .5):
        return np.zeros_like(mask)
    return core.astype(np.uint8) * 255


def load_text_model(root: Path, device: str):
    verify_text_strokes(root)
    import torch
    from safetensors.torch import load_file
    if device not in ("mps", "cpu") or (device == "mps" and not torch.backends.mps.is_available()):
        raise ValueError("Requested text stroke device is unavailable")
    name = "_manga_text_sam"
    package = root/"hi_sam/__init__.py"
    if name in sys.modules and Path(sys.modules[name].__file__).resolve() != package.resolve():
        raise ValueError("Text stroke model package is already loaded from another location")
    if name not in sys.modules:
        spec = importlib.util.spec_from_file_location(name, package, submodule_search_locations=[str(package.parent)])
        module = importlib.util.module_from_spec(spec)
        sys.modules[name] = module
        spec.loader.exec_module(module)
    build = importlib.import_module(f"{name}.modeling.build")
    args = SimpleNamespace(checkpoint=None, model_type="vit_l", attn_layers=1, prompt_len=12, hier_det=False)
    model = build.model_registry["vit_l"](args=args)
    model.load_state_dict(load_file(str(root/MODEL_FILE), device="cpu"), strict=True)
    return torch, model.eval().to(device)


class TextStrokeSegmenter:
    """Two bounded scale views of verified local weights, loaded only on first use."""
    def __init__(self, root: Path, device: str):
        self.torch, self.model = load_text_model(root, device)
        self.device = device

    def __call__(self, image: np.ndarray, bounds: tuple[int, int, int, int]) -> list[np.ndarray]:
        validate_bgr_image(image)
        height, width = image.shape[:2]
        if len(bounds) != 4 or any(type(value) is not int for value in bounds):
            raise ValueError("Text stroke proposal requires four integer coordinates")
        left, top, right, bottom = bounds
        if not 0 <= left < right <= width or not 0 <= top < bottom <= height:
            raise ValueError("Text stroke proposal escapes its source crop")
        variants = (False, True) if max(height, width) < IMAGE_SIZE else (False,)
        return [text_stroke_core(image, self.segment(image, native)) for native in variants]

    def segment(self, image: np.ndarray, native: bool) -> np.ndarray:
        canvas, (scaled_width, scaled_height) = prepare_text_image(image, native=native)
        tensor = self.torch.from_numpy(canvas.astype(np.float32)).permute(2, 0, 1).to(self.device).contiguous()
        with self.torch.inference_mode():
            outputs = self.model([{"image": tensor, "original_size": (IMAGE_SIZE, IMAGE_SIZE)}], multimask_output=False)
        logits = outputs[3]
        if tuple(logits.shape) != (1, 1, IMAGE_SIZE, IMAGE_SIZE) or not self.torch.isfinite(logits).all():
            raise ValueError("Unexpected text stroke model output")
        mask = (logits[0, 0, :scaled_height, :scaled_width] > 0).byte().cpu().numpy() * 255
        return cv2.resize(mask, (image.shape[1], image.shape[0]), interpolation=cv2.INTER_NEAREST)
