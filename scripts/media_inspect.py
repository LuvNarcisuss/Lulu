#!/usr/bin/env python3
"""Extract representative frames and contact sheets for human media review."""
from pathlib import Path
import json
import subprocess
from PIL import Image, ImageDraw
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'docs/media/inspection'
OUT.mkdir(exist_ok=True)
manifest=json.loads((ROOT/'Assets/media-manifest.json').read_text())
rows=[]
for entry in manifest['files']:
    if entry['kind'] != 'video':
        continue
    path=ROOT/entry['local_file']
    row=Image.new('RGB',(960,215),'#f7f1e6')
    ImageDraw.Draw(row).text((8,4),path.stem,fill='black')
    for index,time in enumerate(entry['inspection']['times_seconds']):
        frame=OUT/(path.stem+'-'+str(index)+'.jpg')
        subprocess.run(['ffmpeg','-y','-v','error','-ss',str(time),'-i',str(path),'-frames:v','1','-vf','scale=320:180:force_original_aspect_ratio=decrease',str(frame)],check=True)
        image=Image.open(frame)
        row.paste(image,(index*320+(320-image.width)//2,25))
    row.save(OUT/(path.stem+'-review.jpg'))
    rows.append(row)
canvas=Image.new('RGB',(960,len(rows)*215),'#f7f1e6')
for index,row in enumerate(rows):
    canvas.paste(row,(0,index*215))
canvas.save(OUT/'all-videos.jpg')
print('Wrote representative-frame review sheet for',len(rows),'published clips')
