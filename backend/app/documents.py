"""Bounded upload inspection and isolated text extraction; no archive extraction to disk."""
import io
import json
import re
import subprocess
import sys
import zipfile
from pathlib import PurePosixPath
from defusedxml import ElementTree
from .errors import AppError

MAX_TEXT = 50000
MAX_EXPANDED = 20 * 1024 * 1024

def safe_filename(name):
    return re.sub(r'[\x00-\x1f\x7f]', '', str(name or 'resume').replace('\\','/').split('/')[-1])[:255] or 'resume'

def inspect_upload(name: str, data: bytes, maximum=5242880):
    if not data or len(data)>maximum:
        raise AppError('Upload one non-empty resume up to 5 MB.',413,'upload_size')
    name = safe_filename(name)
    suffix = name.lower().rsplit('.',1)[-1]
    if suffix == 'pdf' and data.startswith(b'%PDF-'):
        return name, 'pdf'
    if suffix != 'docx' or not data.startswith(b'PK\x03\x04'):
        raise AppError('Upload a genuine PDF or DOCX resume.',422,'file_type')
    try:
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            infos = archive.infolist()
            names = [f.filename for f in infos]
            if len(infos)>500 or len(names)!=len(set(names)) or sum(f.file_size for f in infos)>MAX_EXPANDED:
                raise ValueError('Archive limits')
            if not {'[Content_Types].xml','word/document.xml'}.issubset(names):
                raise ValueError('Missing document')
            for f in infos:
                path = PurePosixPath(f.filename)
                if path.is_absolute() or '..' in path.parts or '\\' in f.filename or f.flag_bits & 1 or f.file_size>MAX_EXPANDED:
                    raise ValueError('Unsafe archive')
                if f.file_size>1024*1024 and f.file_size>max(1,f.compress_size)*100:
                    raise ValueError('Archive expansion')
                if any(x in f.filename.lower() for x in ('vbaproject','word/embeddings/','activex/')):
                    raise ValueError('Embedded executable')
            content_type = archive.read('[Content_Types].xml')
            if len(content_type)>65536 or b'macroEnabled' in content_type:
                raise ValueError('Invalid document type')
            ElementTree.fromstring(content_type)
            ElementTree.fromstring(archive.read('word/document.xml'))
    except Exception:
        raise AppError('This DOCX is damaged, encrypted or exceeds safe document limits.',422,'invalid_docx') from None
    return name, 'docx'

def extract_text(data: bytes, file_type: str):
    try:
        result = subprocess.run([sys.executable,'-m','app.extract_child',file_type],
            input=data, capture_output=True, timeout=10, check=False)
        if result.returncode != 0:
            raise ValueError('Extraction failed')
        text = json.loads(result.stdout)['text'].strip()
        if not 40<=len(text)<=MAX_TEXT or '\x00' in text:
            raise ValueError('Text limits')
        return text
    except Exception:
        raise AppError('Could not read resume text. Use an unencrypted DOCX or text-based PDF, up to 20 pages; scanned PDFs need OCR.',422,'extraction_failed') from None
