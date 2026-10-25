import sys
from pathlib import Path

import torch
from diffusers import StableDiffusionPipeline

OUT = Path(r"c:\Users\sudol\arenaOfStonksness\assets\textures")
MODEL = Path(r"C:\Users\sudol\ComfyUI\models\diffusers\dreamshaper-8")
NEGATIVE = "deformed face, extra eyes, crooked nose, asymmetrical clothes, tuxedo, business suit, necktie, two people, back view, photo, text"
JOBS = [
    ("rich_collector", "full body, one cartoon tax man facing camera, symmetrical face, even black coat, yellow vest, briefcase, ink comic, gray background"),
    ("rich_broker", "full body, one cartoon stockbroker facing camera, symmetrical face, even gray suit and tie, briefcase, ink comic, gray background"),
    ("rich_king", "full body, one short cartoon king facing camera, gold crown, long red royal robe and cape, fur collar, not a suit, ink comic, gray background"),
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
    wanted = set(sys.argv[1:]) or {name for name, _prompt in JOBS}
    for name, prompt in JOBS:
        if name not in wanted:
            continue
        image = pipe(
            prompt,
            negative_prompt=NEGATIVE,
            width=512,
            height=768,
            num_inference_steps=30,
            guidance_scale=7.0,
            generator=torch.Generator(device="cuda").manual_seed(18),
        ).images[0]
        dest = OUT / f"{name}.png"
        image.save(dest)
        print(f"saved={dest.name}", flush=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
