#!/usr/bin/env python3
import os
import sys
from PIL import Image, ImageChops

def clean_green_and_grid(img):
    # Ensure image is RGBA
    img = img.convert("RGBA")
    data = img.getdata()
    
    new_data = []
    for item in data:
        r, g, b, a = item
        # Detect bright green background (#00FF00 or close greens)
        if g > 130 and r < 100 and b < 100:
            new_data.append((0, 0, 0, 0)) # Fully transparent
        # Detect exact bright greens or light yellowish greens
        elif g > 180 and r < 150 and b < 150:
            new_data.append((0, 0, 0, 0))
        else:
            new_data.append(item)
            
    img.putdata(new_data)
    return img

def clear_borders(img, border=10):
    # Clear borders of a cell to remove grid lines
    w, h = img.size
    pixels = img.load()
    for y in range(h):
        for x in range(w):
            if x < border or x > w - border or y < border or y > h - border:
                pixels[x, y] = (0, 0, 0, 0)
    return img

def trim_and_center(frames):
    # Find the maximum bounding box dimensions to ensure consistent size and perfect centering
    bboxes = []
    for frame in frames:
        # Get tight bounding box of non-transparent content
        bbox = frame.getbbox()
        if bbox:
            bboxes.append(bbox)
            
    if not bboxes:
        return frames
        
    # Calculate max width and height needed
    max_w = 0
    max_h = 0
    for bbox in bboxes:
        x0, y0, x1, y1 = bbox
        max_w = max(max_w, x1 - x0)
        max_h = max(max_h, y1 - y0)
        
    # Add a bit of padding (e.g. 10px) to make sure there's breathing room
    max_w += 16
    max_h += 16
    
    processed_frames = []
    for frame in frames:
        bbox = frame.getbbox()
        if not bbox:
            # Empty frame, just create an empty image of max dimensions
            processed_frames.append(Image.new("RGBA", (max_w, max_h), (0, 0, 0, 0)))
            continue
            
        x0, y0, x1, y1 = bbox
        content = frame.crop(bbox)
        
        # Create a new transparent canvas of max dimensions
        new_frame = Image.new("RGBA", (max_w, max_h), (0, 0, 0, 0))
        
        # Center the cropped content on the new canvas
        offset_x = (max_w - (x1 - x0)) // 2
        offset_y = (max_h - (y1 - y0)) // 2
        new_frame.paste(content, (offset_x, offset_y))
        
        processed_frames.append(new_frame)
        
    return processed_frames

def process_character(name, sheet_path, output_dir, jumping_col=2, idle_col=1):
    print(f"🎬 Processing {name}...")
    if not os.path.exists(sheet_path):
        print(f"❌ Sprite sheet not found: {sheet_path}")
        return
        
    os.makedirs(output_dir, exist_ok=True)
    
    img = Image.open(sheet_path)
    img = clean_green_and_grid(img)
    
    # Grid parameters (4 columns, 2 rows)
    cell_w = 256
    cell_h = 512
    
    frames = []
    
    # 1. Extract 4 walking frames (Row 0, Cols 0, 1, 2, 3)
    for col in range(4):
        left = col * cell_w
        top = 0
        right = left + cell_w
        bottom = cell_h
        
        cell = img.crop((left, top, right, bottom))
        cell = clear_borders(cell, border=12) # Clear white grid lines
        frames.append(cell)
        
    # 2. Extract Idle frame (Row 1, Col idle_col)
    left = idle_col * cell_w
    top = cell_h
    right = left + cell_w
    bottom = 1024
    cell_idle = img.crop((left, top, right, bottom))
    cell_idle = clear_borders(cell_idle, border=12)
    frames.append(cell_idle)
    
    # 3. Extract Jumping frame (Row 1, Col jumping_col)
    left = jumping_col * cell_w
    top = cell_h
    right = left + cell_w
    bottom = 1024
    cell_jump = img.crop((left, top, right, bottom))
    cell_jump = clear_borders(cell_jump, border=12)
    frames.append(cell_jump)
    
    # 4. Trim and center all frames consistently to prevent stretching or shaking
    frames = trim_and_center(frames)
    
    # 5. Save frames
    for i, frame in enumerate(frames):
        frame.save(os.path.join(output_dir, f"{i}.png"))
        
    print(f"✅ Saved 6 processed frames to {output_dir} (Width: {frames[0].width}px, Height: {frames[0].height}px)")

if __name__ == "__main__":
    script_dir = os.path.dirname(os.path.abspath(__file__))
    project_root = os.path.dirname(script_dir)
    
    temp_dir = os.path.join(project_root, "temp", "images")
    output_base = os.path.join(project_root, "src", "images")
    
    # Define slicing parameters for each character to match their generated sheet layouts
    # jumping_col can be 2 or 3 depending on where the jumping frame landed
    characters = [
        {"name": "SkeletonGuitarist", "file": "SkeletonGuitarist_sheet.png", "jump": 2, "idle": 1},
        {"name": "SkeletonDrummer", "file": "SkeletonDrummer_sheet.png", "jump": 2, "idle": 1},
        {"name": "SkeletonVocalist", "file": "SkeletonVocalist_sheet.png", "jump": 2, "idle": 0},
        {"name": "SkeletonDancer", "file": "SkeletonDancer_sheet.png", "jump": 2, "idle": 1},
        {"name": "SkullDancer", "file": "SkullDancer_sheet.png", "jump": 2, "idle": 1}
    ]
    
    for char in characters:
        sheet_path = os.path.join(temp_dir, char["file"])
        output_dir = os.path.join(output_base, char["name"])
        process_character(char["name"], sheet_path, output_dir, jumping_col=char["jump"], idle_col=char["idle"])
