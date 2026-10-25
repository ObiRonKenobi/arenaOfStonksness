import sys
from pathlib import Path

import torch
from diffusers import StableDiffusionPipeline

OUT = Path(r"c:\Users\sudol\arenaOfStonksness\assets\textures")
MODEL = Path(r"C:\Users\sudol\ComfyUI\models\diffusers\dreamshaper-8")
PROMPT = "full body, one fat asian man facing camera, big belly, baggy black hoodie, sleepy eyes, two arms hanging down, cel shaded ink comic, gray background"
NEGATIVE = "back view, two people, extra arms, backwards head, photo, realistic, cropped, skinny"


def main() -> int:
    pipe = StableDiffusionPipeline.from_pretrained(
        str(MODEL),
        dtype=torch.float16,
        variant="fp16",
        safety_checker=None,
        feature_extractor=None,
        requires_safety_checker=False,
    ).to("cuda")
    pipe.enable_attention_slicing()
    image = pipe(
        PROMPT,
        negative_prompt=NEGATIVE,
        width=512,
        height=768,
        num_inference_steps=30,
        guidance_scale=7.0,
        generator=torch.Generator(device="cuda").manual_seed(8),
    ).images[0]
    dest = OUT / "lazy_try_8.png"
    image.save(dest)
    print(f"saved={dest.name}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
