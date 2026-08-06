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
from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from PIL import Image
from transformers import AutoModelForVision2Seq, AutoProcessor


class ActRequest(BaseModel):
    instruction: str = Field(..., min_length=1)
    image_base64: str = Field(..., min_length=1)
    unnorm_key: Optional[str] = None
    do_sample: bool = False


class OpenVLAService:
    def __init__(self) -> None:
        self.model_id = os.environ.get("OPENVLA_MODEL_ID", "openvla/openvla-7b")
        self.device = os.environ.get("OPENVLA_DEVICE", "cuda:0")
        self.dtype_name = os.environ.get("OPENVLA_TORCH_DTYPE", "bfloat16")
        self.attn_implementation = os.environ.get("OPENVLA_ATTN_IMPLEMENTATION", "flash_attention_2")
        self.api_token = os.environ.get("OPENVLA_API_TOKEN", "").strip()
        self.default_unnorm_key = os.environ.get("OPENVLA_UNNORM_KEY", "").strip() or None
        self.ready = False

        dtype_map = {
            "float16": torch.float16,
            "bfloat16": torch.bfloat16,
            "float32": torch.float32,
        }
        self.dtype = dtype_map.get(self.dtype_name, torch.bfloat16)

        self.processor = AutoProcessor.from_pretrained(self.model_id, trust_remote_code=True)
        self.model = AutoModelForVision2Seq.from_pretrained(
            self.model_id,
            attn_implementation=self.attn_implementation,
            torch_dtype=self.dtype,
            low_cpu_mem_usage=True,
            trust_remote_code=True,
        ).to(self.device)
        self.model.eval()
        self.ready = True

    def validate_token(self, provided_token: Optional[str]) -> None:
        if not self.api_token:
            return
        if provided_token != self.api_token:
            raise HTTPException(status_code=401, detail="Invalid API token")

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

    @torch.inference_mode()
    def act(self, request: ActRequest) -> List[float]:
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


service = OpenVLAService()
app = FastAPI(title="Moqui OpenVLA Service", version="1.0")


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/readyz")
def readyz():
    if not service.ready:
        raise HTTPException(status_code=503, detail="Model not ready")
    return {
        "status": "ready",
        "modelId": service.model_id,
        "device": service.device,
        "dtype": service.dtype_name,
    }


@app.post("/act")
def act(request: ActRequest, x_api_key: Optional[str] = Header(default=None)):
    service.validate_token(x_api_key)
    action = service.act(request)
    return {
        "action": action,
        "modelId": service.model_id,
        "unnormKey": request.unnorm_key or service.default_unnorm_key,
    }
