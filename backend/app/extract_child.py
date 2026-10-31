import io
import json
import sys
import zipfile
from defusedxml import ElementTree
from pypdf import PdfReader
from .documents import MAX_TEXT

def main():
    # Linux resource ceilings complement the process timeout; container memory
    # limits are still required in deployment, including on Windows hosts.
    if sys.platform != 'win32':
        import resource
        resource.setrlimit(resource.RLIMIT_AS,(384*1024*1024,384*1024*1024))
        resource.setrlimit(resource.RLIMIT_CPU,(8,8))
    data=sys.stdin.buffer.read(5242881)
    if len(data)>5242880:
        raise ValueError('Upload too large')
    if sys.argv[1]=='docx':
        with zipfile.ZipFile(io.BytesIO(data)) as archive:
            root=ElementTree.fromstring(archive.read('word/document.xml'))
        ns='{http://schemas.openxmlformats.org/wordprocessingml/2006/main}'
        text='\n'.join(''.join(node.text or '' for node in p.iter(ns+'t')) for p in root.iter(ns+'p'))
    else:
        reader=PdfReader(io.BytesIO(data),strict=True)
        if reader.is_encrypted or len(reader.pages)>20:
            raise ValueError('PDF limits')
        parts=[]
        for page in reader.pages:
            parts.append(page.extract_text() or '')
            if sum(map(len,parts))>MAX_TEXT:
                raise ValueError('Text limits')
        text='\n'.join(parts)
    if len(text)>MAX_TEXT:
        raise ValueError('Text limits')
    sys.stdout.buffer.write(json.dumps({'text':text},ensure_ascii=False).encode('utf-8'))

if __name__=='__main__':
    main()
