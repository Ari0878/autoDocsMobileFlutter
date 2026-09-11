# Identidad visual de PDF - AutoDocs AI

Estos archivos pertenecen al backend Organizacion-equipo-5/autoDocs, no al código Flutter.

## Aplicación
1. En el backend, reemplazar services/exporter.py con el archivo de este paquete y agregar services/pdf_branding.py.
2. Revisar el diff y desplegar el backend en Render siguiendo el flujo habitual del proyecto.
3. Exportar nuevamente un proyecto desde la app. Los PDF descargados anteriormente conservan su diseño anterior.

## Cambios
- Portada con marca AutoDocs AI, azul oscuro/cian, nombre del proyecto, fecha UTC, origen, lenguaje y referencia.
- Encabezados y pies con marca y numeración física consistente con el índice.
- Estilos de impresión claros para tablas y títulos en HTML/WeasyPrint.
- Portada vectorial y ajuste del título largo en ReportLab, sin fuentes ni imágenes externas nuevas.
- Se evita la página final dedicada únicamente a la firma y la entrada del índice sobre sí mismo.
- Conversión de Markdown por Node explícitamente UTF-8 para conservar acentos en Windows.

## Validación
Muestra de cuatro páginas generada con ReportLab sobre datos reales de manofactura_ia; contenido reducido para mostrar el diseño. Páginas renderizadas con Poppler y revisadas visualmente.
La variante HTML se imprimió con Chromium y se revisó visualmente. WeasyPrint no está instalado en este entorno; validar ese motor en el despliegue.
No se modificó ni se desplegó el servidor remoto. Este paquete no altera el análisis ni los endpoints.
