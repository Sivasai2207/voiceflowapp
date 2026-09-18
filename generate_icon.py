from PIL import Image, ImageDraw, ImageFont
import os

# Create base 1024x1024 icon
size = 1024
img = Image.new('RGBA', (size, size), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)

# Draw background circle with gradient-like effect
center = size // 2
radius = size // 2 - 20

# Create a teal gradient background
for i in range(radius, 0, -1):
    ratio = i / radius
    r = int(0 * (1 - ratio) + 20 * ratio)
    g = int(180 * (1 - ratio) + 140 * ratio)
    b = int(216 * (1 - ratio) + 180 * ratio)
    draw.ellipse([center - i, center - i, center + i, center + i], fill=(r, g, b, 255))

# Draw waveform lines
wave_color = (255, 255, 255, 255)
line_width = 60
num_lines = 5
spacing = 40

for idx in range(num_lines):
    x_center = center
    y_center = center
    height = radius * 0.6 * (0.3 + 0.7 * (idx / (num_lines - 1)))
    
    # Draw vertical line with rounded caps
    y_start = y_center - height
    y_end = y_center + height
    
    # Draw as rounded rectangle
    draw.rounded_rectangle(
        [x_center - line_width//2, y_start, x_center + line_width//2, y_end],
        radius=line_width//2,
        fill=wave_color
    )

# Save as PNG
output_dir = '/Users/sivasai/Projects/VoiceFlowApp/Sources/VoiceFlowApp/Resources/Assets.xcassets/AppIcon.appiconset'
os.makedirs(output_dir, exist_ok=True)

sizes = [16, 32, 64, 128, 256, 512, 1024]
for s in sizes:
    for scale in [1, 2]:
        target_size = s * scale
        if target_size <= 1024:
            resized = img.resize((target_size, target_size), Image.LANCZOS)
            resized.save(os.path.join(output_dir, f'icon_{s}x{s}@{scale}x.png'))

print("Icon generated successfully")
