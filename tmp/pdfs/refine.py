from pathlib import Path
p=Path('.dart_tool/autodocs-backend/services/exporter.py');s=p.read_text(encoding='utf-8')
s=s.replace("if style_name in level_by_style:","if style_name in level_by_style and flowable.getPlainText() != 'Tabla de Contenido':")
s=s.replace('''        story.append(Spacer(1, 1*cm))
        story.append(HRFlowable(width="100%", thickness=0.5, color=colors.HexColor('#e2e8f0')))
        story.append(Paragraph("Generado automáticamente por AutoDocs AI", styles['sub']))
''','')
p.write_text(s,encoding='utf-8')
