import logging
from typing import Literal, Optional
import numpy as np

import torch
from diffusers.utils import load_video

logging.basicConfig(level=logging.INFO)

# Recommended resolution for each model (width, height)
RESOLUTION_MAP = {
    "wan2.1-i2v-14b-480p-diffusers": (480, 720),
    "wan2.1-i2v-14b-720p-diffusers": (720, 1280),
}

def generate_video(
    prompt: str,
    num_frames: int = 49,
    width: Optional[int] = None,
    height: Optional[int] = None,
    output_path: str = "./output.mp4",
    exo_video_path: str = "",
    ego_prior_video_path: str = "",
    num_inference_steps: int = 50,
    guidance_scale: float = 5.0,
    num_videos_per_prompt: int = 1,
    seed: int = 42,
    fps: int = 30,
    attention_GGA: Optional[torch.Tensor] = None,
    attention_mask_GGA: Optional[torch.Tensor] = None,
    point_vecs_per_frame: Optional[torch.Tensor] = None,
    cam_rays: Optional[torch.Tensor] = None,
    cos_sim_scaling_factor: float = 1.0,
    do_kv_cache: bool = False,
    pipe = None,
):
    """
    Generates a video based on the given prompt and saves it to the specified path.
    """

    exo_video = load_video(video=exo_video_path)
    ego_prior_video = load_video(video=ego_prior_video_path)

    # Calculate target dimensions based on input parameters
    # If width and height are provided, use them; otherwise infer from videos
    if width is None or height is None:
        # Fallback: use first frame to infer dimensions
        exo_first_frame = exo_video[0] if exo_video else None
        ego_prior_first_frame = ego_prior_video[0] if ego_prior_video else None
        if exo_first_frame and ego_prior_first_frame:
            exo_width, exo_height = exo_first_frame.size
            ego_width, ego_height = ego_prior_first_frame.size
            assert exo_height == ego_height
            width = exo_width + ego_width
            height = exo_height
        else:
            raise ValueError("Cannot infer video dimensions. Please provide width and height.")
    else:
        # Use provided dimensions
        exo_width = width - height  # exo_width = total_width - ego_width
        ego_width = height  # ego_width = height
    
    # Resize videos to target dimensions
    cropped_exo_video = []
    for img in exo_video:
        cropped_img = img.resize((exo_width, height))
        cropped_exo_video.append(cropped_img)
    exo_video = cropped_exo_video

    cropped_ego_prior_video = []
    for img in ego_prior_video:
        cropped_img = img.resize((ego_width, height))
        cropped_ego_prior_video.append(cropped_img)
    ego_prior_video = cropped_ego_prior_video

    video_generate = pipe(
        height=height,
        width=width,
        prompt=prompt,
        exo_video=exo_video,
        ego_prior_video=ego_prior_video, 
        num_videos_per_prompt=num_videos_per_prompt, 
        num_inference_steps=num_inference_steps,
        num_frames=num_frames, 
        guidance_scale=guidance_scale,
        generator=torch.Generator().manual_seed(seed),
        attention_GGA = attention_GGA,
        attention_mask_GGA = attention_mask_GGA,
        point_vecs_per_frame = point_vecs_per_frame,
        cam_rays = cam_rays,
        cos_sim_scaling_factor=cos_sim_scaling_factor,
        do_kv_cache = do_kv_cache,
        ).frames[0]
    
    import imageio
    video_frames = np.clip(video_generate * 255, 0, 255).astype(np.uint8)
    imageio.mimsave(output_path, video_frames, fps=fps)
    print(f"Video saved to: {output_path}")

    return video_generate
