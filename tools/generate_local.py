"""Local concept art and textures via ComfyUI's Stable Diffusion install.

DreamShaper 8 weights live outside the game repo. This script only writes PNGs
into assets/textures.
"""
import sys
from pathlib import Path

import torch
from diffusers import StableDiffusionPipeline

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures"
MODEL = Path(r"C:\Users\sudol\ComfyUI\models\diffusers\dreamshaper-8")

JOBS = [
    ("brick", 512, 512, "square seamless tileable video game albedo texture of a dirty tenement brick wall, bold black ink outlines, cel shaded comic, muddy red bricks, grime in the mortar, flat lighting, no text, no people"),
    ("planks", 512, 512, "square seamless tileable video game albedo texture of worn wooden barricade planks, bold black ink outlines, cel shaded, dirty brown boards with nail holes, flat lighting, no text, no people"),
    ("punk", 512, 768, "character concept sheet, single full body front view, young Hispanic male punk rocker, tall liberty-spike mohawk, shaved sides of the head, high-strung scowl, patched worn leather jacket, ripped jeans, bold black ink outlines, cel shaded comic, dirty saturated colors, plain gray background, no text"),
    ("hobo", 512, 768, "character concept sheet, single full body front view, poor dirty homeless white man, middle-aged, messy unwashed beard, grime and soot on face and hands, torn oversized coat full of holes and patches, stained undershirt, ripped filthy pants, broken mismatched shoes, ragged and destitute, wise tired eyes, bold black ink outlines, cel shaded comic, plain gray background, no text"),
    ("dreads", 512, 768, "character concept sheet, single full body front view, Black woman with long dreadlocks, relaxed expression, jacket, bold black ink outlines, cel shaded comic, dirty saturated colors, plain gray background, no text"),
    ("lazy", 512, 768, "full body, one fat asian man facing camera, big belly, baggy black hoodie, sleepy eyes, two arms hanging down, cel shaded ink comic, gray background"),
    ("rich_horde", 768, 512, "three cartoon villains in a row, tax collector with briefcase, stockbroker in a gray suit, short king in a red royal robe and cape with a gold crown, symmetrical faces, ink comic, gray background"),
]
NEGATIVE = "photorealistic, blurry, text, watermark, logo, extra limbs, cropped, deformed hands, low contrast"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    if not torch.cuda.is_available():
        print("CUDA is not available")
        return 1
    pipe = StableDiffusionPipeline.from_pretrained(
        str(MODEL),
        torch_dtype=torch.float16,
        variant="fp16",
        safety_checker=None,
        feature_extractor=None,
        requires_safety_checker=False,
    )
    pipe = pipe.to("cuda")
    pipe.enable_attention_slicing()
    for name, width, height, prompt in JOBS:
        dest = OUT / f"{name}.png"
        image = pipe(
            prompt,
            negative_prompt=NEGATIVE,
            width=width,
            height=height,
            num_inference_steps=28,
            guidance_scale=7.0,
            generator=torch.Generator(device="cuda").manual_seed(21),
        ).images[0]
        image.save(dest)
        print(f"saved={dest.name}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
