"""AI remaster of original 1991 pictures with local SDXL img2img (diffusers, GPU).

The original is upscaled with nearest-neighbour and used as the img2img init image at a low
denoising strength, so composition, palette and silhouettes stay those of the original art
while the detail is repainted. Sprites (an _rgba.png) get the original transparency mask back.
Writes OUT.png and OUT_compare.png (original | remaster).

Run with remake/tools/.venv_ai (diffusers; torch is shared from an existing CUDA install):
  ai_remaster.py IN.png OUT_base --prompt "..." [--scale 4] [--denoise 0.4] [--seed 1991] [--refine 0.25]
"""
import argparse, os
import numpy as np
import torch
from PIL import Image, ImageFilter
from diffusers import StableDiffusionXLImg2ImgPipeline

MODEL = r"C:\pinokio\api\stable-diffusion-webui\models\Stable-diffusion\sd_xl_base_1.0.safetensors"
STYLE = ("detailed painted illustration in the style of a 1991 VGA military role-playing game, "
         "Poland in the year 2000 after a nuclear war, gritty, muted colours, faithful to the original composition, ")
NEG = ("blurry, lowres, jpeg artifacts, text, watermark, logo, signature, deformed, extra limbs, "
       "anime, cartoon, oversaturated, neon")

_pipe = None


def pipe():
    global _pipe
    if _pipe is None:
        _pipe = StableDiffusionXLImg2ImgPipeline.from_single_file(MODEL, torch_dtype=torch.float16)
        _pipe.to("cuda")
        _pipe.set_progress_bar_config(disable=True)
        _pipe.vae.enable_tiling()        # keeps big pictures inside 12 GB of VRAM
    return _pipe


def scale2x(img):
    """EPX/Scale2x: doubles pixel art, rounding off staircases without blurring."""
    a = np.asarray(img.convert("RGB")).astype(np.int32)
    c = a[..., 0] << 16 | a[..., 1] << 8 | a[..., 2]
    p = np.pad(c, 1, mode="edge")
    B, D, F, H_ = p[:-2, 1:-1], p[1:-1, :-2], p[1:-1, 2:], p[2:, 1:-1]
    e0 = np.where((D == B) & (B != F) & (D != H_), D, c)
    e1 = np.where((B == F) & (B != D) & (F != H_), F, c)
    e2 = np.where((D == H_) & (D != B) & (H_ != F), D, c)
    e3 = np.where((H_ == F) & (D != H_) & (B != F), F, c)
    out = np.zeros((c.shape[0] * 2, c.shape[1] * 2), np.int32)
    out[0::2, 0::2], out[0::2, 1::2], out[1::2, 0::2], out[1::2, 1::2] = e0, e1, e2, e3
    rgb = np.stack([(out >> 16) & 255, (out >> 8) & 255, out & 255], -1).astype(np.uint8)
    return Image.fromarray(rgb)


def paint(rgb, prompt, scale=4, denoise=0.35, seed=1991, steps=30, cfg=6.0, refine=0.25, pixel=False):
    """Original RGB picture -> remastered RGB picture at exactly scale x the original size.
    pixel=True (small sprites): Scale2x enlargement instead of blur, so fine detail survives."""
    W, H = rgb.width * scale, rgb.height * scale
    if pixel:
        soft = rgb
        while soft.width < W:
            soft = scale2x(soft)
        soft = soft.resize((W, H), Image.LANCZOS)
    else:
        # soften the pixel grid so the model repaints detail instead of copying blocks
        soft = rgb.resize((W, H), Image.BICUBIC).filter(ImageFilter.GaussianBlur(scale * 0.5))
    # SDXL wants multiples of 8: pad with the edge pixels, crop back afterwards
    W8, H8 = -(-W // 8) * 8, -(-H // 8) * 8
    pad = Image.new("RGB", (W8, H8))
    pad.paste(soft.resize((W8, H8)), (0, 0))
    pad.paste(soft, (0, 0))
    g = torch.Generator("cuda").manual_seed(seed)
    img = pipe()(prompt=STYLE + prompt, negative_prompt=NEG, image=pad, strength=denoise,
                 num_inference_steps=steps, guidance_scale=cfg, generator=g).images[0]
    img = img.resize((W8, H8), Image.LANCZOS)
    if refine > 0:
        # second, light pass on the painted result adds crisp detail without moving anything
        img = pipe()(prompt=STYLE + prompt + ", sharp focus, fine detail", negative_prompt=NEG, image=img,
                     strength=refine, num_inference_steps=steps, guidance_scale=cfg, generator=g).images[0]
        img = img.resize((W8, H8), Image.LANCZOS)
    torch.cuda.empty_cache()
    return img.crop((0, 0, W, H))


def compare(orig, img, scale):
    big = orig.convert("RGB").resize((orig.width * scale, orig.height * scale), Image.NEAREST)
    cmp = Image.new("RGB", (big.width * 2 + 8, big.height))
    cmp.paste(big, (0, 0))
    cmp.paste(img.convert("RGB"), (big.width + 8, 0))
    return cmp


def remaster(src, out, prompt, scale=4, denoise=0.35, seed=1991, steps=30, cfg=6.0, refine=0.25):
    orig = Image.open(src)
    img = paint(orig.convert("RGB"), prompt, scale, denoise, seed, steps, cfg, refine)
    if orig.mode == "RGBA":
        img = img.convert("RGBA")
        img.putalpha(orig.getchannel("A").resize(img.size, Image.NEAREST))
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    img.save(out + ".png")
    compare(orig, img, scale).save(out + "_compare.png")
    print("wrote", out + ".png", img.size)


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("src"); ap.add_argument("out")
    ap.add_argument("--prompt", required=True)
    ap.add_argument("--scale", type=int, default=4)
    ap.add_argument("--denoise", type=float, default=0.35)
    ap.add_argument("--seed", type=int, default=1991)
    ap.add_argument("--steps", type=int, default=30)
    ap.add_argument("--refine", type=float, default=0.25)
    a = ap.parse_args()
    remaster(a.src, a.out, a.prompt, a.scale, a.denoise, a.seed, a.steps, refine=a.refine)
