import io
import re
import threading
from pathlib import Path
from xml.sax.saxutils import escape
from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.shared import Inches, Pt
from reportlab import __file__ as reportlab_file
from reportlab.lib.enums import TA_JUSTIFY, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import Paragraph, SimpleDocTemplate, Spacer

_font_lock=threading.Lock()

def paragraphs(letter):
    closing=False
    for index,part in enumerate(re.split(r'\n\s*\n',letter)):
        closing=closing or bool(re.match(r'\s*(sincerely|yours|best regards|kind regards|regards)\b',part,re.I))
        left=closing or (index==0 and bool(re.match(r'\s*(dear|to the)\b',part,re.I)))
        yield part,left

def export_docx(letter):
    document=Document()
    section=document.sections[0]
    section.top_margin=section.bottom_margin=Inches(.85)
    section.left_margin=section.right_margin=Inches(.9)
    style=document.styles['Normal']
    style.font.name='Calibri'; style.font.size=Pt(11)
    style.paragraph_format.space_after=Pt(11)
    style.paragraph_format.line_spacing=1.15
    for part,left in paragraphs(letter):
        paragraph=document.add_paragraph(part)
        paragraph.alignment=WD_ALIGN_PARAGRAPH.LEFT if left else WD_ALIGN_PARAGRAPH.JUSTIFY
        paragraph.paragraph_format.widow_control=True
    document.core_properties.title='Cover letter'
    document.core_properties.author=''
    stream=io.BytesIO(); document.save(stream)
    return stream.getvalue()

def export_pdf(letter):
    with _font_lock:
        if 'Firstrole' not in pdfmetrics.getRegisteredFontNames():
            candidates=[Path('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'),Path('C:/Windows/Fonts/arial.ttf'),Path(reportlab_file).parent/'fonts/Vera.ttf']
            path=next(p for p in candidates if p.exists())
            pdfmetrics.registerFont(TTFont('Firstrole',str(path)))
    stream=io.BytesIO()
    doc=SimpleDocTemplate(stream,pagesize=A4,rightMargin=54,leftMargin=54,topMargin=54,bottomMargin=54,
        title='Cover letter',author='')
    story=[]
    for part,left in paragraphs(letter):
        style=ParagraphStyle('letter',fontName='Firstrole',fontSize=11,leading=16,
            alignment=TA_LEFT if left else TA_JUSTIFY,spaceAfter=12,splitLongWords=True)
        story.append(Paragraph(escape(part).replace('\n','<br/>'),style))
    doc.build(story)
    return stream.getvalue()

def export(letter,kind):
    if kind=='docx': return export_docx(letter),'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    if kind=='pdf': return export_pdf(letter),'application/pdf'
    return letter.encode('utf-8'),'text/plain; charset=utf-8'
