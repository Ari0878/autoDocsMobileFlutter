from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED
from pypdf import PdfReader
base=Path('backend_changes')
with ZipFile(base/'autodocs_pdf_branding.zip','w',ZIP_DEFLATED) as z:
    for rel in ['README.md','services/exporter.py','services/pdf_branding.py']:
        z.write(base/rel,rel)
r=PdfReader('output/pdf/autodocs_portada_muestra.pdf')
assert len(r.pages)==4
assert 'AutoDocs' in r.pages[0].extract_text()
assert 'manofactura_ia' in r.pages[0].extract_text()
for i,page in enumerate(r.pages[1:],2):
    text=page.extract_text()
    assert 'Generado por AutoDocs AI' in text
    assert f'{i} / 4' in text
print('PDF checks passed: brand, project name, 4 pages, page numbering.')
