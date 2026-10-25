import sys
from pathlib import Path

import torch
from diffusers import StableDiffusionPipeline

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "assets" / "textures"
MODEL = Path(r"C:\Users\sudol\ComfyUI\models\diffusers\dreamshaper-8")
BASE_NEG = "photorealistic, blurry, text, watermark, logo, extra limbs, cropped, deformed hands, low contrast"
JOBS = [
    (
        "punk",
        512,
        768,
        "character concept sheet, one person only, full body front view, young Hispanic male punk, tall spiked mohawk hairstyle, shaved sides, high-strung scowl, patched worn jacket, ripped jeans, bold black ink outlines, cel shaded comic, plain gray background",
        BASE_NEG + ", neat hair, side part, slicked hair, bald, buzz cut, business suit",
    ),
    (
        "hobo",
        512,
        768,
        "character concept sheet, one person only, full body front view, destitute homeless white man, dirt and soot smeared on face and hands, messy unkempt beard, torn hole-filled overcoat, stained ragged clothes, ripped pants, broken shoes, poor and filthy, tired wise eyes, bold black ink outlines, cel shaded comic, plain gray background",
        BASE_NEG + ", wealthy, rich, clean, groomed, tailored suit, vest, waistcoat, dress shoes, luxury coat, handsome gentleman",
    ),
    (
        "lazy",
        512,
        768,
        "character concept sheet, one person only, full body front view, young overweight Asian man, huge round fat belly, big gut stretching a baggy black hoodie, hoodie too small for his stomach, sleepy half-closed eyes, lazy slouch, sweatpants, bold black ink outlines, cel shaded comic, plain gray background",
        BASE_NEG + ", skinny, slim, thin, athletic, muscular, flat stomach, six pack, fit",
    ),
]


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
    for name, width, height, prompt, negative in JOBS:
        image = pipe(
            prompt,
            negative_prompt=negative,
            width=width,
            height=height,
            num_inference_steps=32,
            guidance_scale=8.5,
            generator=torch.Generator(device="cuda").manual_seed(21),
        ).images[0]
        dest = OUT / f"{name}.png"
        image.save(dest)
        print(f"saved={dest.name}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
