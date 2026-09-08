import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';

class ProjectDetailScreen extends StatefulWidget {
  final String projectId;

  const ProjectDetailScreen({
    super.key,
    required this.projectId,
  });

  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailScreenState();
}

class _ProjectDetailScreenState extends State<ProjectDetailScreen>
    with SingleTickerProviderStateMixin {
  final ApiService _api = ApiService();
  Timer? _pollTimer;

  // Estado
  bool _isLoading = true;
  bool _isAnalyzing = false;
  String? _error;
  Project? _project;
  Map<String, dynamic>? _analysisResults;
  int _currentTab = 0;

  // Selecciones
  final Map<String, List<int>> _selections = {
    'endpoints': [],
    'functions': [],
    'classes': [],
    'structure': [],
  };

  // Controladores para tabs
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadProject();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  // ============================================================
  // CARGA DE DATOS
  // ============================================================

  Future<void> _loadProject() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final projectResponse = await _api.get('/api/projects/${widget.projectId}');
      if (projectResponse.statusCode != 200) {
        throw Exception('Error al cargar proyecto');
      }
      final projectData = projectResponse.data;
      _project = Project.fromJson(projectData);

      if (_project!.status == 'completed') {
        await _loadResults();
        setState(() {
          _isLoading = false;
          _isAnalyzing = false;
        });
      } else if (_project!.status == 'analyzing' || _project!.status == 'pending') {
        setState(() {
          _isLoading = false;
          _isAnalyzing = true;
        });
        _startPolling();
      } else {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _loadResults() async {
    try {
      final response = await _api.get('/api/analysis/${widget.projectId}/results');
      if (response.statusCode == 200) {
        final data = response.data;
        if (data['status'] == 'completed' && data['results'] != null) {
          _analysisResults = data['results'];
          await _loadSelections();
        }
      }
    } catch (e) {
      print('Error loading results: $e');
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (timer) async {
      try {
        final response = await _api.get('/api/analysis/${widget.projectId}/results');
        if (response.statusCode == 200) {
          final data = response.data;
          if (data['status'] == 'completed' && data['results'] != null) {
            _analysisResults = data['results'];
            await _loadSelections();
            if (mounted) {
              setState(() {
                _isAnalyzing = false;
              });
            }
            _pollTimer?.cancel();
          }
        }
      } catch (_) {}
    });
  }

  // ============================================================
  // SELECCIONES
  // ============================================================

  Future<void> _loadSelections() async {
    final storageKey = 'selections_${widget.projectId}';
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(storageKey);
    if (saved != null) {
      try {
        final data = jsonDecode(saved);
        if (mounted) {
          setState(() {
            _selections['endpoints'] = List<int>.from(data['endpoints'] ?? []);
            _selections['functions'] = List<int>.from(data['functions'] ?? []);
            _selections['classes'] = List<int>.from(data['classes'] ?? []);
            _selections['structure'] = List<int>.from(data['structure'] ?? []);
          });
        }
      } catch (_) {}
    }
  }

  void _saveSelections() {
    final storageKey = 'selections_${widget.projectId}';
    SharedPreferences.getInstance().then((prefs) {
      prefs.setString(storageKey, jsonEncode(_selections));
    });
  }

  void _toggleSelection(String type, int index) {
    setState(() {
      final list = _selections[type]!;
      if (list.contains(index)) {
        list.remove(index);
      } else {
        list.add(index);
      }
      _saveSelections();
    });
  }

  void _toggleSelectAll(String type, bool? value) {
    if (value == null) return;
    final list = _analysisResults?[type] ?? [];
    setState(() {
      if (value) {
        _selections[type] = List.generate(list.length, (i) => i);
      } else {
        _selections[type] = [];
      }
      _saveSelections();
    });
  }

  bool _isAllSelected(String type) {
    final list = _analysisResults?[type] ?? [];
    if (list.isEmpty) return false;
    final selected = _selections[type] ?? [];
    return selected.length == list.length;
  }

  // ============================================================
  // EXPORTAR PDF
  // ============================================================

  Future<void> _exportPdf() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _LoadingDialog(
        title: 'Generando PDF',
        message: 'Por favor espere mientras generamos el documento...',
      ),
    );

    try {
      final url = '/api/export/${widget.projectId}/pdf?selected=${Uri.encodeComponent(jsonEncode(_selections))}';
      final response = await _api.get(url);

      if (mounted) Navigator.pop(context);

      if (response.statusCode == 200) {
        _showSuccessDialog('¡PDF Generado!', 'El archivo PDF se descargó correctamente.');
      } else {
        _showErrorDialog('Error al generar PDF', response.data['error'] ?? 'Error desconocido');
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      _showErrorDialog('Error', e.toString());
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Row(
          children: [
            Icon(Icons.error, color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 8),
            Text(title),
          ],
        ),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // MÉTRICAS
  // ============================================================

  int get _totalFiles => _analysisResults?['total_files'] ?? 0;
  int get _totalFunctions => (_analysisResults?['functions'] as List?)?.length ?? 0;
  int get _totalClasses => (_analysisResults?['classes'] as List?)?.length ?? 0;
  int get _totalEndpoints => (_analysisResults?['endpoints'] as List?)?.length ?? 0;
  int get _totalLanguages => (_analysisResults?['languages'] as Map?)?.keys.length ?? 0;
  int get _qualityScore => _analysisResults?['quality_score'] ?? 0;

  String get _qualityDescription {
    final q = _qualityScore;
    if (q >= 70) return 'Buen nivel de documentación y código limpio.';
    if (q >= 40) return 'Nivel aceptable, hay margen de mejora.';
    return 'Se recomienda mejorar la documentación.';
  }

  Color get _qualityColor {
    final q = _qualityScore;
    if (q >= 70) return Colors.green;
    if (q >= 40) return Colors.orange;
    return Colors.red;
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(
            Icons.arrow_back,
            color: theme.colorScheme.onSurface,
          ),
        ),
        title: Text(
          _project?.name ?? 'Análisis',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          // Botón de tema
          IconButton(
            onPressed: () {
              final themeProvider = context.read<ThemeProvider>();
              themeProvider.toggleTheme();
            },
            icon: Icon(
              isDark ? Icons.light_mode : Icons.dark_mode,
              color: theme.colorScheme.onSurface,
            ),
          ),
          // Botón de exportar PDF
          if (_project?.status == 'completed')
            IconButton(
              onPressed: _exportPdf,
              icon: Icon(
                Icons.picture_as_pdf,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(
          color: theme.colorScheme.primary,
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 48,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              _error!,
              style: TextStyle(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadProject,
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: theme.colorScheme.onPrimary,
              ),
              child: const Text('Reintentar'),
            ),
          ],
        ),
      );
    }

    if (_isAnalyzing) {
      return _buildAnalyzingState();
    }

    if (_analysisResults == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.analytics_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No hay resultados de análisis',
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      );
    }

    return _buildResults();
  }

  Widget _buildAnalyzingState() {
    final theme = Theme.of(context);

    return Center(
      child: GlassCard(
        padding: const EdgeInsets.all(32),
        backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Analizando proyecto...',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Esto puede tomar unos segundos dependiendo del tamaño del proyecto.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            GradientButton(
              onPressed: () {
                _pollTimer?.cancel();
                _loadProject();
              },
              text: 'Verificar estado',
              isOutlined: true,
              width: 200,
              height: 40,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    final theme = Theme.of(context);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildMetrics(),
          const SizedBox(height: 16),
          _buildQualityScore(),
          const SizedBox(height: 16),
          _buildTabs(),
          const SizedBox(height: 16),
          _buildTabContent(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ============================================================
  // MÉTRICAS
  // ============================================================

  Widget _buildMetrics() {
    final theme = Theme.of(context);

    final metrics = [
      {'label': 'Archivos', 'value': _totalFiles, 'icon': Icons.insert_drive_file},
      {'label': 'Funciones', 'value': _totalFunctions, 'icon': Icons.functions},
      {'label': 'Clases', 'value': _totalClasses, 'icon': Icons.class_},
      {'label': 'Endpoints', 'value': _totalEndpoints, 'icon': Icons.api},
      {'label': 'Lenguajes', 'value': _totalLanguages, 'icon': Icons.code},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 5,
        childAspectRatio: 1.0,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: metrics.length,
      itemBuilder: (context, index) {
        final metric = metrics[index];
        return GlassCard(
          padding: const EdgeInsets.all(8),
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                metric['icon'] as IconData,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                '${metric['value']}',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                metric['label'] as String,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // SCORE DE CALIDAD
  // ============================================================

  Widget _buildQualityScore() {
    final theme = Theme.of(context);
    final q = _qualityScore;
    final progress = q / 100;

    return GlassCard(
      padding: const EdgeInsets.all(16),
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            height: 80,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(80, 80),
                  painter: ProgressRingPainter(
                    progress: progress.clamp(0.0, 1.0),
                    color: _qualityColor,
                    strokeWidth: 8,
                    isDark: theme.brightness == Brightness.dark,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$q',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 22,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '/100',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Score de Calidad',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _qualityDescription,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // TABS
  // ============================================================

  Widget _buildTabs() {
    final theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.2),
        ),
        color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
      ),
      child: TabBar(
        controller: _tabController,
        onTap: (index) => setState(() => _currentTab = index),
        tabs: const [
          Tab(text: 'Endpoints'),
          Tab(text: 'Funciones'),
          Tab(text: 'Clases'),
          Tab(text: 'Estructura'),
        ],
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.primary.withOpacity(0.1),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
      ),
    );
  }

  // ============================================================
  // TAB CONTENT
  // ============================================================

  Widget _buildTabContent() {
    switch (_currentTab) {
      case 0:
        return _buildEndpointsTable();
      case 1:
        return _buildFunctionsTable();
      case 2:
        return _buildClassesTable();
      case 3:
        return _buildStructureTable();
      default:
        return const SizedBox.shrink();
    }
  }

  // ============================================================
  // TABLA DE ENDPOINTS
  // ============================================================

  Widget _buildEndpointsTable() {
    final theme = Theme.of(context);
    final endpoints = (_analysisResults?['endpoints'] as List?) ?? [];
    final selected = _selections['endpoints'] ?? [];
    final allSelected = _isAllSelected('endpoints');

    return GlassCard(
      padding: EdgeInsets.zero,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (v) => _toggleSelectAll('endpoints', v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  checkColor: Colors.white,
                  activeColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Seleccionar todos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${endpoints.length} endpoints',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                GradientButton(
                  onPressed: _saveSelections,
                  text: 'Guardar',
                  height: 32,
                  fontSize: 11,
                ),
              ],
            ),
          ),
          if (endpoints.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se detectaron endpoints',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(
                  theme.colorScheme.primary.withOpacity(0.08),
                ),
                dataRowColor: WidgetStateProperty.all(
                  Colors.transparent,
                ),
                dividerThickness: 0.5,
                columns: [
                  const DataColumn(label: Text('')),
                  DataColumn(
                    label: Text(
                      'Método',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Ruta',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Framework',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Archivo',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                rows: endpoints.asMap().entries.map((entry) {
                  final index = entry.key;
                  final ep = entry.value;
                  final isSelected = selected.contains(index);
                  final method = ep['method'] ?? 'GET';
                  final methodColor = _getMethodColor(method);

                  return DataRow(
                    color: WidgetStateProperty.all(
                      index % 2 == 0
                          ? theme.colorScheme.primary.withOpacity(0.03)
                          : Colors.transparent,
                    ),
                    cells: [
                      DataCell(
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection('endpoints', index),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          checkColor: Colors.white,
                          activeColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: methodColor.withOpacity(0.15),
                          ),
                          child: Text(
                            method,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: methodColor,
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          ep['path'] ?? '',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          ep['framework'] ?? '—',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          ep['file'] ?? '',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Color _getMethodColor(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return Colors.green;
      case 'POST':
        return Colors.blue;
      case 'PUT':
        return Colors.orange;
      case 'DELETE':
        return Colors.red;
      default:
        return Colors.purple;
    }
  }

  // ============================================================
  // TABLA DE FUNCIONES
  // ============================================================

  Widget _buildFunctionsTable() {
    final theme = Theme.of(context);
    final functions = (_analysisResults?['functions'] as List?) ?? [];
    final selected = _selections['functions'] ?? [];
    final allSelected = _isAllSelected('functions');

    return GlassCard(
      padding: EdgeInsets.zero,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (v) => _toggleSelectAll('functions', v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  checkColor: Colors.white,
                  activeColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Seleccionar todos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${functions.length} funciones',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                GradientButton(
                  onPressed: _saveSelections,
                  text: 'Guardar',
                  height: 32,
                  fontSize: 11,
                ),
              ],
            ),
          ),
          if (functions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se detectaron funciones',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(
                  theme.colorScheme.primary.withOpacity(0.08),
                ),
                dataRowColor: WidgetStateProperty.all(
                  Colors.transparent,
                ),
                dividerThickness: 0.5,
                columns: [
                  const DataColumn(label: Text('')),
                  DataColumn(
                    label: Text(
                      'Nombre',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Archivo',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Parámetros',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Complejidad',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Documentada',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                rows: functions.asMap().entries.map((entry) {
                  final index = entry.key;
                  final fn = entry.value;
                  final isSelected = selected.contains(index);
                  final complexity = fn['complexity'] ?? 1;
                  final isAsync = fn['is_async'] ?? false;
                  final hasDoc = fn['docstring'] != null;

                  return DataRow(
                    color: WidgetStateProperty.all(
                      index % 2 == 0
                          ? theme.colorScheme.primary.withOpacity(0.03)
                          : Colors.transparent,
                    ),
                    cells: [
                      DataCell(
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection('functions', index),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          checkColor: Colors.white,
                          activeColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            if (isAsync)
                              Text(
                                'async ',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.purple,
                                  fontFamily: 'JetBrains Mono',
                                ),
                              ),
                            Text(
                              fn['name'] ?? '',
                              style: TextStyle(
                                fontFamily: 'JetBrains Mono',
                                fontSize: 12,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        Text(
                          fn['file'] ?? '',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          (fn['params'] as List?)?.join(', ') ?? '—',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '$complexity',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: complexity <= 5
                                ? Colors.green
                                : complexity <= 10
                                    ? Colors.orange
                                    : Colors.red,
                          ),
                        ),
                      ),
                      DataCell(
                        hasDoc
                            ? Icon(Icons.check_circle, color: Colors.green, size: 18)
                            : _buildSuggestionButton(fn['name'], fn['file'], fn['params'] ?? []),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSuggestionButton(String name, String file, List params) {
    return InkWell(
      onTap: () => _showSuggestionModal(name, file, params.join(', ')),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.amber.withOpacity(0.12),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb, size: 14, color: Colors.amber),
            const SizedBox(width: 4),
            Text(
              'Sugerencia',
              style: TextStyle(
                fontSize: 9,
                color: Colors.amber.shade800,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuggestionModal(String name, String file, String params) {
    showDialog(
      context: context,
      builder: (context) => _SuggestionDialog(
        name: name,
        file: file,
        params: params,
        kind: 'function',
      ),
    );
  }

  // ============================================================
  // TABLA DE CLASES
  // ============================================================

  Widget _buildClassesTable() {
    final theme = Theme.of(context);
    final classes = (_analysisResults?['classes'] as List?) ?? [];
    final selected = _selections['classes'] ?? [];
    final allSelected = _isAllSelected('classes');

    return GlassCard(
      padding: EdgeInsets.zero,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (v) => _toggleSelectAll('classes', v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  checkColor: Colors.white,
                  activeColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Seleccionar todos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${classes.length} clases',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                GradientButton(
                  onPressed: _saveSelections,
                  text: 'Guardar',
                  height: 32,
                  fontSize: 11,
                ),
              ],
            ),
          ),
          if (classes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se detectaron clases',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(
                  theme.colorScheme.primary.withOpacity(0.08),
                ),
                dataRowColor: WidgetStateProperty.all(
                  Colors.transparent,
                ),
                dividerThickness: 0.5,
                columns: [
                  const DataColumn(label: Text('')),
                  DataColumn(
                    label: Text(
                      'Clase',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Archivo',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Métodos',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Bases',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Documentada',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                rows: classes.asMap().entries.map((entry) {
                  final index = entry.key;
                  final cls = entry.value;
                  final isSelected = selected.contains(index);
                  final hasDoc = cls['docstring'] != null;

                  return DataRow(
                    color: WidgetStateProperty.all(
                      index % 2 == 0
                          ? theme.colorScheme.primary.withOpacity(0.03)
                          : Colors.transparent,
                    ),
                    cells: [
                      DataCell(
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection('classes', index),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          checkColor: Colors.white,
                          activeColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          cls['name'] ?? '',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          cls['file'] ?? '',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          '${(cls['methods'] as List?)?.length ?? 0}',
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          (cls['bases'] as List?)?.join(', ') ?? '—',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      DataCell(
                        hasDoc
                            ? Icon(Icons.check_circle, color: Colors.green, size: 18)
                            : _buildClassSuggestionButton(cls['name'], cls['file']),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildClassSuggestionButton(String name, String file) {
    return InkWell(
      onTap: () => _showClassSuggestionModal(name, file),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: Colors.amber.withOpacity(0.12),
          border: Border.all(color: Colors.amber.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lightbulb, size: 14, color: Colors.amber),
            const SizedBox(width: 4),
            Text(
              'Sugerencia',
              style: TextStyle(
                fontSize: 9,
                color: Colors.amber.shade800,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClassSuggestionModal(String name, String file) {
    showDialog(
      context: context,
      builder: (context) => _SuggestionDialog(
        name: name,
        file: file,
        params: '',
        kind: 'class',
      ),
    );
  }

  // ============================================================
  // TABLA DE ESTRUCTURA
  // ============================================================

  Widget _buildStructureTable() {
    final theme = Theme.of(context);
    final structure = (_analysisResults?['structure'] as List?) ?? [];
    final selected = _selections['structure'] ?? [];
    final allSelected = _isAllSelected('structure');

    return GlassCard(
      padding: EdgeInsets.zero,
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Checkbox(
                  value: allSelected,
                  onChanged: (v) => _toggleSelectAll('structure', v),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  checkColor: Colors.white,
                  activeColor: theme.colorScheme.primary,
                  side: BorderSide(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Seleccionar todos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const Spacer(),
                Text(
                  '${structure.length} archivos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: 8),
                GradientButton(
                  onPressed: _saveSelections,
                  text: 'Guardar',
                  height: 32,
                  fontSize: 11,
                ),
              ],
            ),
          ),
          if (structure.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se detectaron archivos',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                headingRowColor: WidgetStateProperty.all(
                  theme.colorScheme.primary.withOpacity(0.08),
                ),
                dataRowColor: WidgetStateProperty.all(
                  Colors.transparent,
                ),
                dividerThickness: 0.5,
                columns: [
                  const DataColumn(label: Text('')),
                  DataColumn(
                    label: Text(
                      'Ruta',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Lenguaje',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  DataColumn(
                    label: Text(
                      'Tamaño',
                      style: TextStyle(
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
                rows: structure.asMap().entries.map((entry) {
                  final index = entry.key;
                  final file = entry.value;
                  final isSelected = selected.contains(index);
                  final size = file['size'] ?? 0;
                  final sizeStr = size > 1024
                      ? '${(size / 1024).toStringAsFixed(1)} KB'
                      : '$size B';

                  return DataRow(
                    color: WidgetStateProperty.all(
                      index % 2 == 0
                          ? theme.colorScheme.primary.withOpacity(0.03)
                          : Colors.transparent,
                    ),
                    cells: [
                      DataCell(
                        Checkbox(
                          value: isSelected,
                          onChanged: (_) => _toggleSelection('structure', index),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          checkColor: Colors.white,
                          activeColor: theme.colorScheme.primary,
                          side: BorderSide(
                            color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          file['path'] ?? '',
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      DataCell(
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: theme.colorScheme.primary.withOpacity(0.1),
                          ),
                          child: Text(
                            file['language'] ?? 'Desconocido',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ),
                      ),
                      DataCell(
                        Text(
                          sizeStr,
                          style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================
// PROGRESS RING PAINTER
// ============================================================

class ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final bool isDark;

  const ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    this.isDark = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - strokeWidth / 2;

    // Fondo
    final backgroundPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, backgroundPaint);

    // Progreso
    final progressPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final sweepAngle = 2 * 3.14159 * progress.clamp(0.0, 1.0);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -3.14159 / 2,
      sweepAngle,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.isDark != isDark;
  }
}

// ============================================================
// LOADING DIALOG
// ============================================================

class _LoadingDialog extends StatelessWidget {
  final String title;
  final String message;

  const _LoadingDialog({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 48,
              height: 48,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// SUGGESTION DIALOG
// ============================================================

class _SuggestionDialog extends StatefulWidget {
  final String name;
  final String file;
  final String params;
  final String kind;

  const _SuggestionDialog({
    required this.name,
    required this.file,
    required this.params,
    required this.kind,
  });

  @override
  State<_SuggestionDialog> createState() => _SuggestionDialogState();
}

class _SuggestionDialogState extends State<_SuggestionDialog> {
  bool _isLoading = true;
  String? _suggestion;
  String? _error;
  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _generateSuggestion();
  }

  Future<void> _generateSuggestion() async {
    try {
      final response = await _api.post(
        '/api/analysis/suggest-docstring',
        data: {
          'name': widget.name,
          'file': widget.file,
          'params': widget.params,
          'kind': widget.kind,
          'lang': 'Python',
        },
      );

      if (response.statusCode == 200) {
        setState(() {
          _suggestion = response.data['suggestion'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = response.data['error'] ?? 'Error al generar sugerencia';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _copySuggestion() {
    if (_suggestion != null) {
      // Usar Clipboard en Flutter
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(24),
        constraints: const BoxConstraints(maxWidth: 500, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Sugerencia de Docstring',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    Icons.close,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${widget.kind == 'class' ? 'class' : 'def'} ${widget.name}(${widget.params}) — ${widget.file}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontFamily: 'JetBrains Mono',
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _isLoading
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            color: theme.colorScheme.primary,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Generando sugerencia con IA...',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : _error != null
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: theme.colorScheme.error,
                                size: 40,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _error!,
                                style: TextStyle(
                                  color: theme.colorScheme.error,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Copia este docstring en tu código:',
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(12),
                                color: theme.colorScheme.primary.withOpacity(0.05),
                                border: Border.all(
                                  color: theme.colorScheme.outlineVariant.withOpacity(0.2),
                                ),
                              ),
                              child: SingleChildScrollView(
                                child: Text(
                                  _suggestion!,
                                  style: TextStyle(
                                    fontFamily: 'JetBrains Mono',
                                    fontSize: 12,
                                    height: 1.6,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            GradientButton(
                              onPressed: _copySuggestion,
                              text: 'Copiar al portapapeles',
                              icon: Icons.copy,
                              width: double.infinity,
                              height: 40,
                              fontSize: 12,
                            ),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}