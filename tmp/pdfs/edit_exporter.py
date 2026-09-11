from pathlib import Path
p=Path('.dart_tool/autodocs-backend/services/exporter.py')
s=p.read_text(encoding='utf-8')
s='from html import escape\nfrom services.pdf_branding import cover_html, PRINT_CSS, draw_cover\n'+s
s=s.replace('</style>', '{PRINT_CSS}\n</style>',1)
a=s.index('  <div class="doc-header">');b=s.index('  <div class="toc">',a)
s=s[:a]+'  {cover_html(self.project, self.results)}\n'+s[b:]
a=s.index('        # Portada simplificada');b=s.index('        # Índice',a)
s=s[:a]+'''        # Cover is drawn as vector elements by the first-page callback.
        story.append(Spacer(1, 1))
        story.append(PageBreak())

'''+s[b:]
s=s.replace('doc.multiBuild(story, canvasmaker=_NumberedCanvas)', '''def first_page(canvas, document):
            draw_cover(canvas, self.project, self.results, *A4)

        doc.multiBuild(story, onFirstPage=first_page, canvasmaker=_NumberedCanvas)''')
a=s.index('                page_num = self._pageNumber - self._SKIPPED_PAGES');b=s.index('\n        doc = ',a)
s=s[:a]+'''                if self._pageNumber == 1:
                    return
                self.saveState()
                self.setStrokeColor(colors.HexColor('#e2e8f0'))
                self.setLineWidth(.5)
                self.line(2.5*cm, A4[1]-1.8*cm, A4[0]-2.5*cm, A4[1]-1.8*cm)
                self.setFont('Helvetica-Bold', 8)
                self.setFillColor(colors.HexColor('#0369a1'))
                self.drawString(2.5*cm, A4[1]-1.5*cm, 'AutoDocs AI')
                self.setFont('Helvetica', 8)
                self.setFillColor(colors.HexColor('#64748b'))
                self.drawRightString(A4[0]-2.5*cm, A4[1]-1.5*cm, 'DOCUMENTACIÓN TÉCNICA')
                self.drawString(2.5*cm, 1.2*cm, 'Generado por AutoDocs AI')
                self.drawRightString(A4[0]-2.5*cm, 1.2*cm,
                                     f'{self._pageNumber} / {content_pages + self._SKIPPED_PAGES}')
                self.restoreState()
''' + s[b:]
s=s.replace('Paragraph(f"{project_name}", styles[\'title\'])', 'Paragraph(escape(project_name), styles[\'title\'])')
p.write_text(s,encoding='utf-8')
