#
# This software is in the public domain under CC0 1.0 Universal plus a
# Grant of Patent License.
#
# To the extent possible under law, the author(s) have dedicated all
# copyright and related and neighboring rights to this software to the
# public domain worldwide. This software is distributed without any
# warranty.
#
# You should have received a copy of the CC0 Public Domain Dedication
# along with this software (see the LICENSE.md file). If not, see
# <http://creativecommons.org/publicdomain/zero/1.0/>.
#
import base64
import io
import os
from typing import List, Optional

import torch
from fastapi import FastAPI, Header, HTTPException, Query
from pydantic import BaseModel, Field
from PIL import Image
from transformers import AutoModelForVision2Seq, AutoModelForZeroShotObjectDetection, AutoProcessor


class ActRequest(BaseModel):
    instruction: str = Field(..., min_length=1)
    image_base64: str = Field(..., min_length=1)
    unnorm_key: Optional[str] = None
    do_sample: bool = False


class GroundRequest(BaseModel):
    instruction: str = Field(..., min_length=1)
    image_base64: str = Field(..., min_length=1)
    return_target_pose: bool = False
    target_pose_dimension: int = Field(default=6, ge=1, le=16)


class OpenVLAService:
    def __init__(self) -> None:
        self.model_id = os.environ.get("OPENVLA_MODEL_ID", "openvla/openvla-7b")
        requested_device = os.environ.get("OPENVLA_DEVICE", "cuda:0")
        self.dtype_name = os.environ.get("OPENVLA_TORCH_DTYPE", "bfloat16")
        self.attn_implementation = os.environ.get("OPENVLA_ATTN_IMPLEMENTATION", "flash_attention_2")
        self.api_token = os.environ.get("OPENVLA_API_TOKEN", "").strip()
        self.default_unnorm_key = os.environ.get("OPENVLA_UNNORM_KEY", "").strip() or None
        self.startup_error: Optional[str] = None

        dtype_map = {
            "float16": torch.float16,
            "bfloat16": torch.bfloat16,
            "float32": torch.float32,
        }
        self.dtype = dtype_map.get(self.dtype_name, torch.bfloat16)
        self.grounding_model_id = os.environ.get("OPENVLA_GROUNDING_MODEL_ID", "google/owlv2-base-patch16-ensemble")
        requested_grounding_device = os.environ.get("OPENVLA_GROUNDING_DEVICE", requested_device)
        self.grounding_box_threshold = float(os.environ.get("OPENVLA_GROUNDING_BOX_THRESHOLD", "0.12"))
        self.grounding_text_threshold = float(os.environ.get("OPENVLA_GROUNDING_TEXT_THRESHOLD", "0.10"))
        self.grounding_max_labels = max(1, int(os.environ.get("OPENVLA_GROUNDING_MAX_LABELS", "8")))
        self.target_pose_defaults = self._parse_float_list(
            os.environ.get("OPENVLA_TARGET_POSE_DEFAULTS", "0,0,0,0,0,0")
        )
        self.target_pose_scale = self._parse_float_list(
            os.environ.get("OPENVLA_TARGET_POSE_SCALE", "1,1,1,0,0,0")
        )
        self.target_pose_bias = self._parse_float_list(
            os.environ.get("OPENVLA_TARGET_POSE_BIAS", "0,0,0,0,0,0")
        )
        self.grounding_processor = None
        self.grounding_model = None
        self.processor = None
        self.model = None
        self.device = self.resolve_device(requested_device)
        self.grounding_device = self.resolve_device(requested_grounding_device)

    def resolve_device(self, requested_device: str) -> str:
        normalized = (requested_device or "cpu").strip().lower()
        if normalized.startswith("cuda") and not torch.cuda.is_available():
            return "cpu"
        return requested_device

    def ensure_action_model(self) -> None:
        if self.processor is not None and self.model is not None:
            return
        self.processor = AutoProcessor.from_pretrained(self.model_id, trust_remote_code=True)
        self.model = AutoModelForVision2Seq.from_pretrained(
            self.model_id,
            attn_implementation=self.attn_implementation,
            torch_dtype=self.dtype,
            low_cpu_mem_usage=True,
            trust_remote_code=True,
        ).to(self.device)
        self.model.eval()

    def validate_token(self, provided_token: Optional[str]) -> None:
        if not self.api_token:
            return
        if provided_token != self.api_token:
            raise HTTPException(status_code=401, detail="Invalid API token")

    def _parse_float_list(self, raw_value: str) -> List[float]:
        values: List[float] = []
        for part in raw_value.split(","):
            part = part.strip()
            if not part:
                continue
            values.append(float(part))
        return values or [0.0]

    def build_prompt(self, instruction: str) -> str:
        lowered = instruction.strip().lower()
        if "v01" in self.model_id:
            return (
                "A chat between a curious user and an artificial intelligence assistant. "
                f"USER: What action should the robot take to {lowered}? ASSISTANT:"
            )
        return f"In: What action should the robot take to {lowered}?\nOut:"

    def decode_image(self, image_base64: str) -> Image.Image:
        payload = image_base64
        if "," in image_base64 and image_base64.split(",", 1)[0].startswith("data:"):
            payload = image_base64.split(",", 1)[1]
        raw = base64.b64decode(payload)
        return Image.open(io.BytesIO(raw)).convert("RGB")

    def ensure_grounding_model(self) -> None:
        if self.grounding_processor is not None and self.grounding_model is not None:
            return
        self.grounding_processor = AutoProcessor.from_pretrained(self.grounding_model_id, trust_remote_code=True)
        self.grounding_model = AutoModelForZeroShotObjectDetection.from_pretrained(
            self.grounding_model_id,
            trust_remote_code=True,
        ).to(self.grounding_device)
        self.grounding_model.eval()

    def build_grounding_queries(self, instruction: str) -> List[str]:
        lowered = instruction.strip().lower()
        separators = ["|", ",", ";", "\n"]
        parts = [lowered]
        for separator in separators:
            if separator in lowered:
                parts = [piece.strip() for piece in lowered.split(separator) if piece.strip()]
                break

        cleaned: List[str] = []
        for part in parts:
            compact = " ".join(part.split())
            for prefix in (
                "find the ",
                "find ",
                "locate the ",
                "locate ",
                "detect the ",
                "detect ",
                "ground the ",
                "ground ",
                "where is the ",
                "where is ",
                "show the ",
                "show ",
            ):
                if compact.startswith(prefix):
                    compact = compact[len(prefix):].strip()
                    break
            compact = compact.strip(" .?!:")
            if compact:
                cleaned.append(compact)

        if lowered not in cleaned:
            cleaned.insert(0, lowered)
        unique_queries: List[str] = []
        for query in cleaned:
            if query not in unique_queries:
                unique_queries.append(query)
            if len(unique_queries) >= self.grounding_max_labels:
                break
        return unique_queries

    def build_target_pose(
        self,
        center_x_norm: float,
        center_y_norm: float,
        box_width_norm: float,
        box_height_norm: float,
        confidence: float,
        dimension: int,
    ) -> List[float]:
        basis = [center_x_norm, center_y_norm, box_width_norm, box_height_norm, confidence, 1.0]
        pose: List[float] = []
        for idx in range(dimension):
            default_value = self.target_pose_defaults[idx] if idx < len(self.target_pose_defaults) else 0.0
            scale_value = self.target_pose_scale[idx] if idx < len(self.target_pose_scale) else 0.0
            bias_value = self.target_pose_bias[idx] if idx < len(self.target_pose_bias) else 0.0
            basis_value = basis[idx] if idx < len(basis) else 0.0
            pose.append(default_value + (basis_value * scale_value) + bias_value)
        return pose

    @torch.inference_mode()
    def act(self, request: ActRequest) -> List[float]:
        self.ensure_action_model()
        image = self.decode_image(request.image_base64)
        prompt = self.build_prompt(request.instruction)
        inputs = self.processor(prompt, image).to(self.device, dtype=self.dtype)
        kwargs = {"do_sample": request.do_sample}
        unnorm_key = request.unnorm_key or self.default_unnorm_key
        if unnorm_key:
            kwargs["unnorm_key"] = unnorm_key
        action = self.model.predict_action(**inputs, **kwargs)
        if hasattr(action, "tolist"):
            return action.tolist()
        return list(action)

    @torch.inference_mode()
    def ground(self, request: GroundRequest) -> dict:
        self.ensure_grounding_model()
        image = self.decode_image(request.image_base64)
        queries = self.build_grounding_queries(request.instruction)
        inputs = self.grounding_processor(text=[queries], images=image, return_tensors="pt").to(self.grounding_device)
        outputs = self.grounding_model(**inputs)
        target_sizes = torch.tensor([image.size[::-1]], device=self.grounding_device)
        if hasattr(self.grounding_processor, "post_process_grounded_object_detection"):
            results = self.grounding_processor.post_process_grounded_object_detection(
                outputs=outputs,
                input_ids=inputs.input_ids,
                threshold=self.grounding_box_threshold,
                text_threshold=self.grounding_text_threshold,
                target_sizes=target_sizes,
            )
        else:
            results = self.grounding_processor.post_process_object_detection(
                outputs=outputs,
                threshold=self.grounding_box_threshold,
                target_sizes=target_sizes,
            )
        detections = results[0]
        boxes = detections.get("boxes", [])
        scores = detections.get("scores", [])
        labels = detections.get("labels", [])
        if len(boxes) == 0:
            raise HTTPException(status_code=404, detail=f"No grounding match found for instruction '{request.instruction}'.")

        best_index = max(range(len(boxes)), key=lambda idx: float(scores[idx]))
        selected_box = boxes[best_index].tolist() if hasattr(boxes[best_index], "tolist") else list(boxes[best_index])
        score = float(scores[best_index])
        label_idx = int(labels[best_index]) if len(labels) > best_index else 0
        object_label = queries[label_idx] if 0 <= label_idx < len(queries) else queries[0]

        x_min, y_min, x_max, y_max = [float(value) for value in selected_box]
        width_px = max(0.0, x_max - x_min)
        height_px = max(0.0, y_max - y_min)
        center_x = x_min + (width_px / 2.0)
        center_y = y_min + (height_px / 2.0)
        image_width, image_height = image.size
        center_x_norm = center_x / max(1.0, float(image_width))
        center_y_norm = center_y / max(1.0, float(image_height))
        width_norm = width_px / max(1.0, float(image_width))
        height_norm = height_px / max(1.0, float(image_height))

        target_pose = None
        if request.return_target_pose:
            target_pose = self.build_target_pose(
                center_x_norm=center_x_norm,
                center_y_norm=center_y_norm,
                box_width_norm=width_norm,
                box_height_norm=height_norm,
                confidence=score,
                dimension=request.target_pose_dimension,
            )

        return {
            "boundingBox": [x_min, y_min, x_max, y_max],
            "center": [center_x, center_y],
            "targetPose": target_pose,
            "objectLabel": object_label,
            "confidence": score,
            "coordinateSystem": "image-pixel",
            "modelId": self.grounding_model_id,
        }


service = OpenVLAService()
app = FastAPI(title="Moqui OpenVLA Service", version="1.0")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    return {
        "status": "ready",
        "modelId": service.model_id,
        "device": service.device,
        "dtype": service.dtype_name,
        "groundingModelId": service.grounding_model_id,
        "groundingDevice": service.grounding_device,
        "actionModelLoaded": service.model is not None,
        "groundingModelLoaded": service.grounding_model is not None,
    }


@app.post("/act")
def act(
    request: ActRequest,
    x_api_key: Optional[str] = Header(default=None),
    apiKey: Optional[str] = Query(default=None),
):
    service.validate_token(x_api_key or apiKey)
    action = service.act(request)
    return {
        "action": action,
        "modelId": service.model_id,
        "unnormKey": request.unnorm_key or service.default_unnorm_key,
    }


@app.post("/ground")
def ground(
    request: GroundRequest,
    x_api_key: Optional[str] = Header(default=None),
    apiKey: Optional[str] = Query(default=None),
):
    service.validate_token(x_api_key or apiKey)
    return service.ground(request)
