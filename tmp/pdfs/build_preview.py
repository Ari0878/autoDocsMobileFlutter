import sys
from pathlib import Path
sys.path.insert(0,str(Path('.dart_tool/autodocs-backend').resolve()))
from services.analyzer import ProjectAnalyzer
from services.exporter import DocumentExporter
results=ProjectAnalyzer('.dart_tool/manofactura-fixture').analyze()
md='''# 1. Resumen del proyecto
El proyecto manofactura_ia implementa un sistema de información manufacturera. Su código incluye módulos de producción, mantenimiento y análisis de calidad.
## 1.1 Alcance del análisis
Esta muestra utiliza los resultados del análisis estático del repositorio. La portada identifica el sistema que genera el documento y mantiene el nombre del proyecto como referencia principal.
## 1.2 Estructura técnica
| Elemento | Resultado |
| --- | --- |
| Lenguaje principal | Python |
| Archivos detectados | 64 |
| Funciones | 195 |
| Endpoints | 55 |
# 2. Referencia de código
A continuación se presenta una selección de funciones detectadas en el código fuente.
'''
for f in results['functions'][:8]:
    md+=f"\n## {f.get('name','Función')}\nArchivo: `{f.get('file','')}`\n\n"
    md+=str(f.get('docstring') or 'Función identificada por el analizador de código de AutoDocs AI.')+'\n'
project={'_id':'manofactura-ia-muestra','name':'manofactura_ia','github_url':'https://github.com/stsus20/manofactura_ia.git'}
e=DocumentExporter(project,{'results':results,'documentation':{'full_markdown':md}})
e._pdf_with_reportlab('output/pdf/autodocs_portada_muestra.pdf')
Path('tmp/pdfs/muestra.html').write_text(e.to_html(),encoding='utf-8')
from pypdf import PdfReader
r=PdfReader('output/pdf/autodocs_portada_muestra.pdf')
print('Pages:',len(r.pages));print(r.pages[0].extract_text())
