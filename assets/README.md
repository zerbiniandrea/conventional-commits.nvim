# Demo Assets

## How the demo GIF was created

### Recording with asciinema
```bash
asciinema rec -c "nvim" demo.cast
```

### Converting to GIF
```bash
~/.cargo/bin/agg --font-family "JetBrainsMono Nerd Font Mono" demo.cast demo.gif
```

### Cropping and trimming
```bash
# Crop to window area (x=725, y=60, width=820, height=740)
# Trim from 1s to 24s
ffmpeg -ss 1 -to 24 -i demo.gif -vf "crop=820:740:725:60" demo-cropped.gif -y

# Optimize file size
ffmpeg -ss 1 -to 24 -i demo.gif -vf "crop=820:740:725:60,fps=10,split[s0][s1];[s0]palettegen=max_colors=128[p];[s1][p]paletteuse=dither=bayer:bayer_scale=3" demo-optimized.gif -y
```

### Recording with wf-recorder (for demo_recorded.gif)
```bash
wf-recorder -g "$(slurp)" -f recording.mp4
# Then convert to GIF with ffmpeg
```

## Notes

- Some emojis don't render properly when using asciinema/agg due to font limitations
- The recorded version (demo_recorded.gif) has all emojis but lower quality
- Kitty opacity was set to 1.0 temporarily for clearer recording
