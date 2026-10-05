"""Source outlines locate balloon interiors; clean pixels never define their boundaries."""
import cv2
import numpy as np
import text_region_geometry as geometry


def light_background(image: np.ndarray) -> np.ndarray:
    return (image.min(axis=2) >= 205) & (np.ptp(image.astype(np.int16), axis=2) <= 55)


def white_background_ratio(image: np.ndarray, box: dict, font_size: float) -> float:
    height, width = image.shape[:2]
    pad = max(2, font_size * .2)
    x1, y1 = max(0, int(box["x"] * width - pad)), max(0, int(box["y"] * height - pad))
    x2, y2 = min(width, int((box["x"] + box["width"]) * width + pad)), min(height, int((box["y"] + box["height"]) * height + pad))
    crop = image[y1:y2, x1:x2]
    return float(light_background(crop).mean()) if crop.size else 0


class BalloonGeometry:
    def __init__(self, source: np.ndarray, text_mask: np.ndarray | None = None):
        self.source = source
        self.height, self.width = source.shape[:2]
        if text_mask is not None and text_mask.shape != source.shape[:2]:
            raise ValueError("Text mask dimensions do not match the source page")
        self.text_mask = text_mask
        gray = cv2.cvtColor(source, cv2.COLOR_BGR2GRAY)
        self.ink = (gray < 180).astype(np.uint8) * 255
        self.edges = cv2.Canny(gray, 40, 100)
        self.contours = {}

    def shape(self, box: dict, font_size: float) -> dict | None:
        contour = self.enclosure(box, font_size)
        if contour is None:
            return None
        mask, x, y = contour
        center = (box["x"] + box["width"] / 2) * self.width - x
        return sampled_shape(mask, x, y, self.width, self.height, center)

    def enclosure(self, box: dict, font_size: float) -> tuple | None:
        """Keep every lobe in a pixel mask until source columns have been separated."""
        x, y, w, h = (box[key] * scale for key, scale in (("x", self.width), ("y", self.height), ("width", self.width), ("height", self.height)))
        if w < 1 or h < 1:
            return None
        center_x, center_y = x + w / 2, y + h / 2
        text_points = self.text_points(x, y, w, h)
        patch = self.source[max(0, int(y)):min(self.height, int(y + h)), max(0, int(x)):min(self.width, int(x + w))]
        if patch.size == 0:
            return None
        glyphs = self.glyphs(int(x), int(y), patch.shape[1], patch.shape[0])
        colors = patch[glyphs == 0]
        if len(colors) < patch.shape[0] * patch.shape[1] * .1:
            return None
        background = np.median(colors, axis=0)
        different = ((~background_matches(patch, background)) & (glyphs == 0)
                     & (np.abs(patch.astype(np.float32) - background).max(axis=2) > 45)).astype(np.uint8)
        _, _, sizes, _ = cv2.connectedComponentsWithStats(different, 8)
        if len(sizes) > 1 and sizes[1:, 4].max() > patch.shape[0] * patch.shape[1] * .25:
            return None
        kernel = 9 if font_size >= 45 else 5
        if kernel not in self.contours:
            self.contours[kernel] = []
            for mask in (self.ink, self.edges):
                barrier = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel, kernel)))
                cv2.rectangle(barrier, (0, 0), (self.width - 1, self.height - 1), 255, 1)
                contours, _ = cv2.findContours(barrier, cv2.RETR_LIST, cv2.CHAIN_APPROX_SIMPLE)
                self.contours[kernel].extend(contours)
        candidates = []
        for contour in self.contours[kernel] + self.colored_contours(background, font_size):
            area = cv2.contourArea(contour)
            bx, by, bw, bh = cv2.boundingRect(contour)
            minimum_area = .45 if text_points is not None else .9
            if not w * h * minimum_area <= area <= self.width * self.height * .20 or bw < w * .8 or bh < h * .75:
                continue
            # Leave room for two connected lobes with narrow Japanese columns;
            # separate_shared_balloons partitions their individual reading areas.
            if bw > max(w * 4, font_size * 12) or bh > max(h * 4, font_size * 12):
                continue
            # A panel can be mostly white and contain the text, but its center is
            # unrelated to that dialogue. Keep placement anchored to the source ink.
            anchored = abs(bx + bw / 2 - center_x) <= max(w, font_size * 3) and abs(by + bh / 2 - center_y) <= max(h, font_size * 3)
            local = np.zeros((bh, bw), np.uint8)
            cv2.drawContours(local, [contour - [bx, by]], -1, 255, -1)
            if not self.contains_text(local, bx, by, (x, y, w, h), text_points):
                continue
            # Border ink describes geometry, not the interior's background color.
            interior = cv2.erode(local, np.ones((3, 3), np.uint8))
            patch = self.source[by:by + bh, bx:bx + bw]
            excluded = (self.glyphs(bx, by, bw, bh) > 0) & ~background_matches(patch, background)
            writable = (interior > 0) & ~excluded
            if np.count_nonzero(writable) < np.count_nonzero(local) * .6:
                continue  # A closed glyph outline is not a reading enclosure.
            colors = self.source[by:by + bh, bx:bx + bw][writable]
            uniform = background_matches(colors, background).mean() if len(colors) else 0
            if uniform < .75:
                continue
            if not anchored:
                shape = sampled_shape(local, bx, by, self.width, self.height, center_x - bx)
                if shape is None or not self.caption_space(shape, (bx, by, bw, bh), (x, y, w, h), font_size, background):
                    continue
            candidates.append((area, bx, by, local))
        if not candidates:
            return None
        _, bx, by, mask = min(candidates, key=lambda item: item[0])
        return mask, bx, by

    def glyphs(self, x: int, y: int, width: int, height: int) -> np.ndarray:
        if self.text_mask is None:
            return np.zeros((height, width), np.uint8)
        return self.text_mask[y:y + height, x:x + width]

    def colored_contours(self, background: np.ndarray, font_size: float) -> list:
        # Color-filled dotted balloons need not have a continuous ink border.
        # Gray/white paper is excluded so an open page cannot become an enclosure.
        if np.ptp(background) < 15 or background.min() < 90:
            return []
        mask = (np.abs(self.source.astype(np.int16) - background).max(axis=2) <= 14).astype(np.uint8) * 255
        kernel = max(3, min(17, int(font_size * .35) | 1))
        closed = cv2.morphologyEx(mask, cv2.MORPH_CLOSE, cv2.getStructuringElement(cv2.MORPH_ELLIPSE, (kernel, kernel)))
        contours, _ = cv2.findContours(closed, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        return list(contours)

    def caption_space(self, shape: dict, bounds: tuple, text: tuple, font_size: float, background: np.ndarray) -> bool:
        """Only a wide, centered line in an otherwise empty rectangle may relax the center anchor."""
        bx, by, bw, bh = bounds
        x, y, w, h = text
        if w < h * 3 or w < bw * .65 or abs(x + w / 2 - bx - bw / 2) > bw * .1 or not geometry.rectangular_enclosure(shape):
            return False
        inset = max(2, int(np.ceil(font_size * .2)))
        patch = self.source[by + inset:by + bh - inset, bx + inset:bx + bw - inset]
        if patch.size == 0:
            return False
        outside = np.ones(patch.shape[:2], np.uint8)
        pad = max(2, font_size * .35)
        left, top = max(0, int(x - pad - bx - inset)), max(0, int(y - pad - by - inset))
        right, bottom = min(patch.shape[1], int(np.ceil(x + w + pad - bx - inset))), min(patch.shape[0], int(np.ceil(y + h + pad - by - inset)))
        outside[top:bottom, left:right] = 0
        count = np.count_nonzero(outside)
        if count < outside.size * .5:
            return False
        different = ((np.abs(patch.astype(np.float32) - background).max(axis=2) > 30) & (outside > 0)).astype(np.uint8)
        if np.count_nonzero(different) > count * .01:
            return False
        _, _, sizes, _ = cv2.connectedComponentsWithStats(different, 8)
        return len(sizes) == 1 or sizes[1:, 4].max() <= max(4, font_size * font_size * .25)

    def text_points(self, x: float, y: float, w: float, h: float) -> tuple | None:
        if self.text_mask is None:
            return None
        left, top = max(0, int(x)), max(0, int(y))
        ys, xs = np.nonzero(self.text_mask[top:min(self.height, int(np.ceil(y + h))), left:min(self.width, int(np.ceil(x + w)))])
        return (xs + left, ys + top) if len(xs) else None

    @staticmethod
    def contains_text(mask: np.ndarray, bx: int, by: int, rectangle: tuple, points: tuple | None) -> bool:
        height, width = mask.shape
        if points is not None:
            xs, ys = points[0] - bx, points[1] - by
            inside = (xs >= 0) & (xs < width) & (ys >= 0) & (ys < height)
            return np.count_nonzero(mask[ys[inside], xs[inside]]) >= len(xs) * .96
        x, y, w, h = rectangle
        area = mask[max(0, int(y - by)):min(height, int(np.ceil(y + h - by))),
                    max(0, int(x - bx)):min(width, int(np.ceil(x + w - bx)))]
        full_area = (int(np.ceil(x + w)) - int(x)) * (int(np.ceil(y + h)) - int(y))
        return full_area > 0 and np.count_nonzero(area) >= full_area * .90


def background_matches(colors: np.ndarray, reference: np.ndarray) -> np.ndarray:
    """Colored translucent balloons retain hue while their brightness and saturation vary."""
    ordinary = np.abs(colors.astype(np.float32) - reference).max(axis=-1) <= 30
    anchor = cv2.cvtColor(np.uint8([[reference]]), cv2.COLOR_BGR2HSV)[0, 0]
    if anchor[1] < 55 or anchor[2] < 150:
        return ordinary
    hsv = cv2.cvtColor(colors.reshape(1, -1, 3), cv2.COLOR_BGR2HSV).reshape(colors.shape)
    hue = np.abs(hsv[..., 0].astype(np.int16) - int(anchor[0]))
    same_color = (np.minimum(hue, 180 - hue) <= 10) & (hsv[..., 1] >= 35) & (hsv[..., 2] >= max(130, int(anchor[2]) - 60))
    return ordinary | same_color


def sampled_shape(mask: np.ndarray, x: int, y: int, width: int, height: int, center_x: float) -> dict | None:
    rows = []
    for local_y in np.unique(np.linspace(0, mask.shape[0] - 1, min(192, mask.shape[0])).astype(int)):
        xs = np.flatnonzero(mask[local_y])
        if len(xs) > 1:
            runs = np.split(xs, np.flatnonzero(np.diff(xs) > 1) + 1)
            run = min(runs, key=lambda part: abs((part[0] + part[-1]) / 2 - center_x))
            if len(run) > 1:
                rows.append({"y": (y + int(local_y)) / height, "left": (x + int(run[0])) / width, "right": (x + int(run[-1]) + 1) / width})
    if len(rows) < 3:
        return None
    return {"bounds": {"x": x / width, "y": y / height, "width": mask.shape[1] / width, "height": mask.shape[0] / height}, "rows": rows}


def balloon_shape(image: np.ndarray, box: dict, font_size: float, original: np.ndarray | None = None) -> dict | None:
    return BalloonGeometry(image if original is None else original).shape(box, font_size)
