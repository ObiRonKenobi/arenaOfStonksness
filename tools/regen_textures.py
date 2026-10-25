import sys
from pathlib import Path

import torch
from diffusers import StableDiffusionPipeline

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures"
MODEL = Path(r"C:\Users\sudol\ComfyUI\models\diffusers\dreamshaper-8")
JOBS = [
    ("brick", "flat orthographic seamless tileable texture, the entire image is only a brick wall, no perspective, no floor, no lights, no windows, bold black outlines between muddy red bricks, cel shaded comic, grime in the mortar, video game albedo"),
    ("planks", "flat orthographic seamless tileable texture, the entire image is horizontal wooden barricade planks, nail holes, bold black ink outlines, cel shaded, dirty brown boards, no room, no perspective, no people"),
]
NEGATIVE = "photograph, perspective, hallway, floor, ceiling, lights, windows, people, text, blurry, 3d render"


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
    for name, prompt in JOBS:
        image = pipe(
            prompt,
            negative_prompt=NEGATIVE,
            width=512,
            height=512,
            num_inference_steps=30,
            guidance_scale=8.0,
            generator=torch.Generator(device="cuda").manual_seed(7),
        ).images[0]
        dest = OUT / f"{name}.png"
        image.save(dest)
        print(f"saved={dest.name}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
