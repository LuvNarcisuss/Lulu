from pathlib import Path
import hashlib, json, re, sys
from reportlab.pdfgen import canvas
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib import colors
from reportlab.platypus import SimpleDocTemplate, Paragraph, Spacer
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.enums import TA_LEFT
root = Path(sys.argv[1]) if len(sys.argv) > 1 else Path('docs/backend/legal')
font=Path('Assets/fonts/Kalam-Regular.ttf')
fonts=list(Path('Assets').rglob('*.ttf'))
body=next((x for x in fonts if 'Kalam' not in x.name),None)
# Embed a legible local TrueType face for selectable policy text.
body=Path('/System/Library/Fonts/Supplemental/Arial.ttf')
pdfmetrics.registerFont(TTFont('PolicyBody',str(body)))
styles=getSampleStyleSheet()
styles.add(ParagraphStyle(name='PolicyTitle',fontName='PolicyBody',fontSize=21,leading=27,textColor=colors.HexColor('#123e3c'),spaceAfter=16))
styles.add(ParagraphStyle(name='PolicyHeading',fontName='PolicyBody',fontSize=13,leading=18,textColor=colors.HexColor('#123e3c'),spaceBefore=12,spaceAfter=6,keepWithNext=True))
styles.add(ParagraphStyle(name='PolicyText',fontName='PolicyBody',fontSize=10,leading=15,spaceAfter=9))
manifest={}
for name in ['terms','privacy']:
    source=root/f'{name}.md'; target=root/f'{name}.pdf'; story=[]
    lines = source.read_text().splitlines()
    title = lines[0].removeprefix('# ')
    app_name = title.split(' — ', 1)[0]
    version = re.search(r'\d{4}-\d{2}-\d{2}-v\d+', lines[1]).group()
    for line in lines:
        text=line.strip().replace('&','&amp;')
        if not text: continue
        if text.startswith('# '): style=styles['PolicyTitle']; text=text[2:]
        elif text.startswith('## '): style=styles['PolicyHeading']; text=text[3:]
        else: style=styles['PolicyText']
        story.append(Paragraph(text,style))
    def footer(c,doc):
        c.setFont('PolicyBody',8);c.setFillColor(colors.HexColor('#5a706c'));c.drawString(44,25,f'{app_name} · {version}');c.drawRightString(568,25,str(doc.page))
    SimpleDocTemplate(str(target),title=title,author=app_name,pagesize=(612,792),rightMargin=44,leftMargin=44,topMargin=40,bottomMargin=45).build(story,onFirstPage=footer,onLaterPages=footer)
    manifest[name]={k:hashlib.sha256(p.read_bytes()).hexdigest() for k,p in [('sourceSHA256',source),('pdfSHA256',target)]}
(root/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
