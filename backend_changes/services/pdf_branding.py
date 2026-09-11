from datetime import datetime
from html import escape


def cover_data(project, results):
    return {
        'name': str(project.get('name') or 'Proyecto'),
        'date': datetime.utcnow().strftime('%d/%m/%Y %H:%M UTC'),
        'language': str(results.get('primary_language') or project.get('language') or 'No especificado'),
        'source': 'Repositorio GitHub' if project.get('github_url') else 'Archivo de proyecto',
        'reference': str(project.get('_id') or 'Sin referencia'),
    }


def cover_html(project, results):
    d = {k: escape(v) for k, v in cover_data(project, results).items()}
    return f'''<section class="autodocs-cover">
      <div class="ad-brand">&lt;/&gt; &nbsp; AutoDocs <span>AI</span></div>
      <div class="ad-tag">DEL CÓDIGO A LA DOCUMENTACIÓN</div>
      <div class="ad-kicker">INFORME DE PROYECTO</div>
      <div class="ad-title">{d['name']}</div>
      <div class="ad-subtitle">Documentación técnica</div>
      <div class="ad-rule"></div>
      <table class="ad-meta"><tr><td>GENERADO<br><b>{d['date']}</b></td>
      <td>LENGUAJE PRINCIPAL<br><b>{d['language']}</b></td></tr>
      <tr><td>ORIGEN<br><b>{d['source']}</b></td><td>REFERENCIA<br><b>{d['reference']}</b></td></tr></table>
      <div class="ad-signature">GENERADO POR AUTODOCS AI<br><span>Análisis de código · Documentación de software</span></div>
    </section>'''


PRINT_CSS = '''
.autodocs-cover { font-family: Arial, sans-serif; text-align:left; background:#fff; color:#0f172a; padding:32px; border-top:12px solid #38bdf8; }
.ad-brand { background:#0f172a; color:white; padding:24px; font-size:26px; font-weight:bold; }
.ad-brand span { color:#38bdf8; }
.ad-tag { background:#0f172a; color:#94a3b8; padding:0 24px 24px; font-size:10px; letter-spacing:2px; }
.ad-kicker { margin-top:85px; color:#0369a1; font-size:10px; letter-spacing:2px; font-weight:bold; }
.ad-title { margin-top:20px; font-size:34px; line-height:1.18; font-weight:bold; overflow-wrap:anywhere; }
.ad-subtitle { margin-top:18px; font-size:20px; color:#475569; }
.ad-rule { width:64px; border-top:4px solid #38bdf8; margin-top:28px; }
.ad-meta { margin-top:48px; width:100%; table-layout:fixed; }
.ad-meta td { border:0; background:white !important; color:#64748b; font-size:9px; padding:10px 10px 10px 0; text-align:left; overflow-wrap:anywhere; }
.ad-meta b { display:block; color:#0f172a; font-size:11px; line-height:1.5; margin-top:6px; }
.ad-signature { margin-top:40px; color:#0369a1; font-weight:bold; font-size:10px; letter-spacing:1px; }
.ad-signature span { display:block; margin-top:8px; color:#64748b; font-size:10px; letter-spacing:0; font-weight:normal; }
@media print {
 @page { size:A4; margin:20mm; @top-left { content:"AutoDocs AI / Documentación técnica"; font:8pt Arial; color:#64748b; } @bottom-left { content:"GENERADO POR AUTODOCS AI"; font:7pt Arial; color:#0369a1; } @bottom-center { content:none; } @bottom-right { content:counter(page) " / " counter(pages); font:8pt Arial; color:#64748b; } }
 @page:first { @top-left { content:none; } @bottom-left { content:none; } @bottom-right { content:none; } }
 :root { --bg:#fff; --surface:#f1f5f9; --border:#cbd5e1; --text:#334155; --white:#0f172a; --muted:#64748b; --accent:#0369a1; --accent2:#334155; }
 .autodocs-cover { padding:0; height:250mm; position:relative; page-break-after:always; }
 .ad-signature { position:absolute; bottom:8mm; left:0; right:0; border-top:1px solid #e2e8f0; padding-top:6mm; }
 .ad-brand { padding-top:14mm; font-size:28pt; }
 .ad-tag { padding-bottom:14mm; }
 .ad-meta { margin-top:20mm; }
 .ad-title { font-size:32pt; }
 .toc { border:0; border-top:2px solid #38bdf8; border-radius:0; background:#f8fafc; }
 .material-icons, .material-symbols-outlined { display:none; }
 .content h1, .content h2, .content h3 { color:#0f172a; }
 .content h2 { border-left-color:#38bdf8; }
 .report-table th, th { background:#0f172a !important; color:white !important; }
 .report-table td, td { color:#334155; }
 pre { background:#f1f5f9; } pre code, code { color:#0369a1; }
 .doc-footer { background:#f8fafc; border-radius:0; }
}
'''


def draw_cover(canvas, project, results, width, height):
    from reportlab.lib.colors import HexColor
    from reportlab.lib.styles import ParagraphStyle
    from reportlab.platypus import Paragraph, KeepInFrame
    d = cover_data(project, results)
    canvas.saveState()
    canvas.setFillColor(HexColor('#0f172a'))
    canvas.rect(0, height-220, width, 220, fill=1, stroke=0)
    canvas.setFillColor(HexColor('#38bdf8'))
    canvas.rect(0, height-224, width, 4, fill=1, stroke=0)
    canvas.setFont('Helvetica-Bold', 25)
    canvas.drawString(55, height-90, '</>')
    canvas.setFillColor(HexColor('#ffffff'))
    canvas.drawString(120, height-90, 'AutoDocs')
    canvas.setFillColor(HexColor('#38bdf8'))
    canvas.drawString(242, height-90, 'AI')
    canvas.setFont('Helvetica', 9)
    canvas.setFillColor(HexColor('#94a3b8'))
    canvas.drawString(55, height-126, 'DEL CÓDIGO A LA DOCUMENTACIÓN')
    canvas.setFillColor(HexColor('#0369a1'))
    canvas.setFont('Helvetica-Bold', 9)
    canvas.drawString(55, height-280, 'INFORME DE PROYECTO')
    title = Paragraph(escape(d['name']), ParagraphStyle('CoverName', fontName='Helvetica-Bold', fontSize=34, leading=40, textColor=HexColor('#0f172a')))
    fitted = KeepInFrame(width-110, 140, [title], mode='shrink', hAlign='LEFT', vAlign='TOP')
    _, h = fitted.wrapOn(canvas, width-110, 140)
    fitted.drawOn(canvas, 55, height-308-h)
    canvas.setFont('Helvetica', 19)
    canvas.setFillColor(HexColor('#475569'))
    canvas.drawString(55, height-480, 'Documentación técnica')
    canvas.setStrokeColor(HexColor('#38bdf8'))
    canvas.setLineWidth(4)
    canvas.line(55, height-503, 112, height-503)
    for x,y,label,value in [(55,245,'GENERADO',d['date']), (310,245,'LENGUAJE PRINCIPAL',d['language']), (55,176,'ORIGEN',d['source']), (310,176,'REFERENCIA',d['reference'])]:
        canvas.setFillColor(HexColor('#64748b')); canvas.setFont('Helvetica',8)
        canvas.drawString(x,y,label)
        p=Paragraph(escape(value),ParagraphStyle('CoverMeta',fontName='Helvetica',fontSize=10,leading=14,textColor=HexColor('#0f172a')))
        _,h=p.wrapOn(canvas, width-x-55 if x>55 else 225,45)
        p.drawOn(canvas,x,y-10-h)
    canvas.setStrokeColor(HexColor('#e2e8f0'));canvas.setLineWidth(.6)
    canvas.line(55,100,width-55,100)
    canvas.setFillColor(HexColor('#0369a1'));canvas.setFont('Helvetica-Bold',8)
    canvas.drawString(55,77,'GENERADO POR AUTODOCS AI')
    canvas.setFillColor(HexColor('#64748b'));canvas.setFont('Helvetica',8)
    canvas.drawString(55,61,'Análisis de código · Documentación de software')
    canvas.restoreState()
