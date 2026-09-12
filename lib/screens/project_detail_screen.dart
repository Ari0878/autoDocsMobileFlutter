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
import '../services/pdf_file_writer.dart';
import '../utils/constants.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

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
  bool _isDisposed = false;

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

  // Colaboradores
  List<Map<String, dynamic>> _contributors = [];
  int _contributorsCount = 0;
  bool _isLoadingContributors = false;

  DateTime? _pollStarted;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadProject();
  }

  @override
  void dispose() {
    _isDisposed = true;
    _pollTimer?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  void _safeSetState(VoidCallback fn) {
    if (mounted && !_isDisposed) setState(fn);
  }

  // ============================================================
  // CARGA DE DATOS
  // ============================================================

  Future<void> _loadProject() async {
    if (_refreshing) return;
    _pollTimer?.cancel();
    _pollStarted = DateTime.now();
    _safeSetState(() {
      _isLoading = true;
      _isAnalyzing = false;
      _error = null;
    });
    await _refreshAnalysis();
  }

  Future<void> _refreshAnalysis() async {
    if (_refreshing || !mounted) return;
    _refreshing = true;
    try {
      final response = await _api.get('/api/projects/${widget.projectId}');
      if (!mounted || _isDisposed) return;

      _project = Project.fromJson(response.data);
      debugPrint('[Análisis] estado: ${_project!.status}');

      if (_project!.hasError) {
        throw StateError(_project!.errorMessage ?? 'El servidor no pudo analizar el proyecto.');
      }

      if (_project!.isCompleted) {
        await _loadResults();
        if (!mounted || _isDisposed) return;
        _safeSetState(() {
          _isLoading = false;
          _isAnalyzing = false;
        });
        _loadContributorsCount();
        return;
      }

      if (!_project!.isPending && !_project!.isAnalyzing) {
        throw StateError('Estado desconocido: ${_project!.status}');
      }

      if (DateTime.now().difference(_pollStarted!) >= const Duration(minutes: 10)) {
        throw StateError('El servidor sigue procesando. Detén la consulta y actualiza manualmente.');
      }

      _safeSetState(() {
        _isLoading = false;
        _isAnalyzing = true;
      });

      _pollTimer = Timer(const Duration(seconds: 3), _refreshAnalysis);
    } catch (e) {
      if (!mounted || _isDisposed) return;
      _safeSetState(() {
        _isLoading = false;
        _isAnalyzing = false;
        _error = e.toString().replaceAll('Exception: ', '').replaceAll('StateError: ', '');
      });
    } finally {
      _refreshing = false;
    }
  }

  Future<void> _loadResults() async {
    final response = await _api.get('/api/analysis/${widget.projectId}/results');
    if (!mounted || _isDisposed) return;
    final data = response.data;
    if (data is! Map || data['status'] != 'completed' || data['results'] is! Map) {
      throw StateError('Sin resultados disponibles.');
    }
    _analysisResults = Map<String, dynamic>.from(data['results']);
    await _loadSelections();
  }

  Future<void> _startAnalysis() async {
    if (_isLoading || _refreshing) return;
    _pollTimer?.cancel();
    _safeSetState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      await _api.post('/api/analysis/${widget.projectId}/start');
      if (!mounted || _isDisposed) return;
      await _loadProject();
    } catch (e) {
      if (!mounted || _isDisposed) return;
      _safeSetState(() {
        _isLoading = false;
        _isAnalyzing = false;
        _error = e.toString();
      });
    }
  }

  // ============================================================
  // COLABORADORES
  // ============================================================

  Future<void> _loadContributorsCount() async {
    try {
      final response = await _api.get('/api/projects/${widget.projectId}/contributors');
      if (response.statusCode == 200) {
        final data = response.data;
        final list = data['contributors'] as List? ?? [];
        _safeSetState(() {
          _contributorsCount = list.length;
        });
      }
    } catch (e) {
      debugPrint('Error cargando colaboradores: $e');
    }
  }

  Future<void> _loadContributors() async {
    _safeSetState(() => _isLoadingContributors = true);
    try {
      final response = await _api.get('/api/projects/${widget.projectId}/contributors');
      if (response.statusCode == 200) {
        final data = response.data;
        final list = (data['contributors'] as List? ?? []);
        _contributors = list.map<Map<String, dynamic>>((c) {
          return {
            'name': c['name']?.toString() ?? c['username']?.toString() ?? 'Desconocido',
            'email': c['email']?.toString() ?? '',
            'commits': _safeParseInt(c['commits']),
            'role': c['role']?.toString() ?? 'contributor',
            'avatar_url': c['avatar_url']?.toString(),
          };
        }).toList();
        _contributors.sort((a, b) => (b['commits'] as int).compareTo(a['commits'] as int));
      }
    } catch (e) {
      debugPrint('Error: $e');
    } finally {
      _safeSetState(() => _isLoadingContributors = false);
    }
  }

  int _safeParseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  Color _glassSurfaceBackground(ThemeData theme, {double lightOpacity = 0.55, double darkOpacity = 0.35}) {
    return theme.colorScheme.surfaceContainerHighest
        .withOpacity(_isDark ? darkOpacity : lightOpacity);
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return _isDark ? const Color(0xFF4ADE80) : const Color(0xFF15803D);
      case 'analyzing':
        return _isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
      case 'pending':
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case 'error':
        return _isDark ? const Color(0xFFF87171) : const Color(0xFFBA1A1A);
      default:
        return Theme.of(context).colorScheme.onSurfaceVariant;
    }
  }

  Color _complexityColor(int complexity) {
    if (complexity <= 5) {
      return _isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);
    }
    if (complexity <= 10) {
      return _isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);
    }
    return _isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626);
  }

  Color get _docSuccessColor =>
      _isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A);

  (Color background, Color foreground) _methodBadgeColors(String method) {
    switch (method.toUpperCase()) {
      case 'GET':
        return _isDark
            ? (const Color(0xFF14532D), const Color(0xFF4ADE80))
            : (const Color(0xFFDCFCE7), const Color(0xFF15803D));
      case 'POST':
        return _isDark
            ? (const Color(0xFF1E3A8A), const Color(0xFF60A5FA))
            : (const Color(0xFFDBEAFE), const Color(0xFF1D4ED8));
      case 'PUT':
        return _isDark
            ? (const Color(0xFF713F12), const Color(0xFFFBBF24))
            : (const Color(0xFFFEF9C3), const Color(0xFFA16207));
      case 'DELETE':
        return _isDark
            ? (const Color(0xFF7F1D1D), const Color(0xFFF87171))
            : (const Color(0xFFFEE2E2), const Color(0xFFB91C1C));
      default:
        return _isDark
            ? (const Color(0xFF581C87), const Color(0xFFC084FC))
            : (const Color(0xFFF3E8FF), const Color(0xFF7E22CE));
    }
  }

  void _showContributorsModal() async {
    await _loadContributors();
    if (!mounted || _isDisposed) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ContributorsModal(
        contributors: _contributors,
        isLoading: _isLoadingContributors,
        onRefresh: () async {
          await _loadContributors();
        },
      ),
    );
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
        if (mounted && !_isDisposed) {
          _safeSetState(() {
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
    _safeSetState(() {
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
    _safeSetState(() {
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

  bool _isExporting = false;

  Future<void> _exportPdf() async {
    if (_isExporting) return;
    if (_totalSelectedCount == 0) {
      _showErrorDialog(
        'Nada seleccionado',
        'Marca al menos un endpoint, función, clase o archivo en las pestañas de abajo antes de generar el PDF.',
      );
      return;
    }
    _safeSetState(() => _isExporting = true);
    try {
      final bytes = await _api.downloadProjectPdf(widget.projectId, _selections);
      if (!mounted || _isDisposed) return;
      final name = (_project?.name ?? 'proyecto')
          .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
      final saved = await savePdf('${name}_documentacion.pdf', bytes);
      if (!mounted || !saved || _isDisposed) return;
      _showSuccessDialog(
        kIsWeb ? 'Descarga iniciada' : 'PDF guardado',
        kIsWeb ? 'Revisa las descargas de tu navegador.' : 'El PDF se guardó.',
      );
    } catch (e) {
      if (mounted && !_isDisposed) {
        _showErrorDialog('Error al descargar PDF', e.toString());
      }
    } finally {
      if (mounted && !_isDisposed) _safeSetState(() => _isExporting = false);
    }
  }

  void _showSuccessDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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

  // Total de elementos marcados entre los 4 tipos (endpoints, funciones,
  // clases y estructura). Se usa para mostrar el contador junto al botón
  // PDF y para avisar si el usuario intenta exportar sin elegir nada.
  int get _totalSelectedCount =>
      _selections.values.fold<int>(0, (sum, list) => sum + list.length);

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(context, isDark),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // BARRA SUPERIOR
  // ============================================================
  //
  // FIX OVERFLOW (66px): antes era un Row único con Spacer() entre
  // "Volver al dashboard" y el grupo de botones (Colaboradores, tema,
  // PDF). Spacer() necesita un ancho acotado para funcionar y, en
  // pantallas angostas, la suma de anchos fijos de los botones superaba
  // el ancho disponible -> RenderFlex overflowed.
  //
  // Solución: usar un Wrap con spaceBetween. Wrap nunca desborda: si no
  // cabe todo en una línea, el grupo de acciones simplemente pasa a la
  // siguiente línea en vez de recortarse o desbordar.
  Widget _buildTopBar(BuildContext context, bool isDark) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 8,
        runSpacing: 8,
        children: [
          // Botón "Volver al dashboard"
          InkWell(
            onTap: () => Navigator.pop(context),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.arrow_back,
                    size: 16,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Volver al dashboard',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                      fontFamily: 'JetBrains Mono',
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Grupo de acciones: Colaboradores, tema, PDF
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Botón Colaboradores
              InkWell(
                onTap: _showContributorsModal,
                borderRadius: BorderRadius.circular(10),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: theme.colorScheme.secondary.withOpacity(0.1),
                    border: Border.all(
                      color: theme.colorScheme.secondary.withOpacity(0.25),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.group,
                        size: 16,
                        color: theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Colaboradores',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10),
                          color: theme.colorScheme.secondary.withOpacity(0.15),
                        ),
                        child: Text(
                          '$_contributorsCount',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Botón de tema
              IconButton(
                onPressed: () {
                  final themeProvider = context.read<ThemeProvider>();
                  themeProvider.toggleTheme();
                },
                icon: Icon(
                  isDark ? Icons.light_mode : Icons.dark_mode,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: _glassSurfaceBackground(theme, lightOpacity: 0.5, darkOpacity: 0.35),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.all(8),
                  minimumSize: const Size(36, 36),
                ),
              ),
              const SizedBox(width: 8),
              // Botón PDF
              if (_project?.status == 'completed')
                InkWell(
                  onTap: _isExporting ? null : _exportPdf,
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      color: theme.colorScheme.primary,
                    ),
                    child: _isExporting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text(
                            _totalSelectedCount > 0 ? 'PDF ($_totalSelectedCount)' : 'PDF',
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // BODY
  // ============================================================

  Widget _buildBody() {
    final theme = Theme.of(context);

    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(color: theme.colorScheme.primary),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            backgroundColor: _glassSurfaceBackground(theme),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  'Error',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    GradientButton(
                      onPressed: _loadProject,
                      text: 'Reintentar',
                      height: 40,
                      fontSize: 12,
                    ),
                    if (_project != null && !_project!.isCompleted && !_project!.isAnalyzing) ...[
                      const SizedBox(width: 8),
                      GradientButton(
                        onPressed: _startAnalysis,
                        text: 'Iniciar análisis',
                        isOutlined: true,
                        height: 40,
                        fontSize: 12,
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
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
              'No hay resultados',
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

  // ============================================================
  // ESTADO DE ANÁLISIS
  // ============================================================

  Widget _buildAnalyzingState() {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: GlassCard(
          padding: const EdgeInsets.all(32),
          backgroundColor: _glassSurfaceBackground(theme),
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
              if (_project?.isPending == true) ...[
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _startAnalysis,
                  child: const Text('Iniciar análisis'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // RESULTADOS
  // ============================================================

  Widget _buildResults() {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProjectCard(),
          const SizedBox(height: 16),
          _buildMetrics(),
          const SizedBox(height: 16),
          _buildQualityScore(),
          const SizedBox(height: 16),
          _buildTabs(),
          const SizedBox(height: 16),
          _buildTabContent(),
        ],
      ),
    );
  }

  // ============================================================
  // TARJETA DEL PROYECTO
  // ============================================================

  Widget _buildProjectCard() {
    final theme = Theme.of(context);

    final statusLabels = {
      'completed': '✓ Completado',
      'analyzing': '⟳ Analizando',
      'pending': '○ Pendiente',
      'error': '✕ Error',
    };

    final status = _project?.status ?? 'pending';
    final statusColor = _statusColor(status);

    return GlassCard(
      padding: const EdgeInsets.all(20),
      backgroundColor: _glassSurfaceBackground(theme),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _project?.name ?? 'Cargando...',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 22,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Lenguaje: ',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                          TextSpan(
                            text: _project?.language ?? '—',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ],
                      ),
                    ),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Creado: ',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                          TextSpan(
                            text: _project != null
                                ? '${_project!.createdAt.day}/${_project!.createdAt.month}/${_project!.createdAt.year}'
                                : '—',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                              fontFamily: 'JetBrains Mono',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: statusColor.withOpacity(0.1),
              border: Border.all(color: statusColor.withOpacity(0.2)),
            ),
            child: Text(
              statusLabels[status] ?? status,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: statusColor,
              ),
            ),
          ),
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
      {'label': 'ARCHIVOS', 'value': _totalFiles, 'icon': Icons.insert_drive_file},
      {'label': 'FUNCIONES', 'value': _totalFunctions, 'icon': Icons.functions},
      {'label': 'CLASES', 'value': _totalClasses, 'icon': Icons.class_},
      {'label': 'ENDPOINTS', 'value': _totalEndpoints, 'icon': Icons.api},
      {'label': 'LENGUAJES', 'value': _totalLanguages, 'icon': Icons.code},
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 480;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: isNarrow ? 3 : 5,
            childAspectRatio: isNarrow ? 1.1 : 0.95,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: metrics.length,
          itemBuilder: (context, index) {
            final metric = metrics[index];
            return GlassCard(
              padding: const EdgeInsets.all(8),
              backgroundColor: _glassSurfaceBackground(theme),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    metric['icon'] as IconData,
                    color: theme.colorScheme.primary,
                    size: 22,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${metric['value']}',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    metric['label'] as String,
                    style: TextStyle(
                      fontSize: 7,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 0.5,
                      fontFamily: 'JetBrains Mono',
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            );
          },
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
      padding: const EdgeInsets.all(20),
      backgroundColor: _glassSurfaceBackground(theme),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            height: 100,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(100, 100),
                  painter: ProgressRingPainter(
                    progress: progress.clamp(0.0, 1.0),
                    color: _qualityColor,
                    strokeWidth: 10,
                    isDark: theme.brightness == Brightness.dark,
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$q',
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 26,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '/100',
                      style: TextStyle(
                        fontSize: 10,
                        color: theme.colorScheme.onSurfaceVariant,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Score de Calidad',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _qualityDescription,
                  style: TextStyle(
                    fontSize: 13,
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
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.outlineVariant.withOpacity(0.2),
          ),
        ),
      ),
      child: TabBar(
        controller: _tabController,
        onTap: (index) => _safeSetState(() => _currentTab = index),
        tabs: const [
          Tab(text: 'API Endpoints'),
          Tab(text: 'Funciones'),
          Tab(text: 'Clases'),
          Tab(text: 'Estructura'),
        ],
        labelColor: theme.colorScheme.primary,
        unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(fontSize: 12),
        indicatorColor: theme.colorScheme.primary,
        indicatorWeight: 2,
        dividerColor: Colors.transparent,
        isScrollable: true,
        tabAlignment: TabAlignment.start,
      ),
    );
  }

  // ============================================================
  // CONTENIDO DE TABS
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
      backgroundColor: _glassSurfaceBackground(theme, lightOpacity: 0.45, darkOpacity: 0.28),
      child: Column(
        children: [
          _buildTableHeader('endpoints', endpoints.length, allSelected),
          if (endpoints.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se detectaron endpoints',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (_isCompact(constraints)) {
                  return _buildMobileList(
                    itemCount: endpoints.length,
                    itemBuilder: (context, index) {
                      final ep = endpoints[index];
                      final isSelected = selected.contains(index);
                      final method = ep['method'] ?? 'GET';
                      final methodBadge = _methodBadgeColors(method);
                      return _buildMobileCard(
                        isSelected: isSelected,
                        onCheckboxChanged: () => _toggleSelection('endpoints', index),
                        topRight: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: methodBadge.$1,
                          ),
                          child: Text(
                            method,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: methodBadge.$2,
                            ),
                          ),
                        ),
                        title: _buildCodeText(ep['path'] ?? ''),
                        rows: [
                          _mobileFieldRow('Framework', ep['framework'] ?? '—'),
                          _mobileFieldRow('Archivo', ep['file'] ?? '—', isFile: true),
                        ],
                      );
                    },
                  );
                }

                return _buildScrollableTable(
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowHeight: 40,
                    dataRowHeight: 48,
                    headingRowColor: WidgetStateProperty.all(
                      theme.colorScheme.primary.withOpacity(0.08),
                    ),
                    columns: [
                      const DataColumn(label: Text('')),
                      _buildColumnHeader('MÉTODO'),
                      _buildColumnHeader('RUTA'),
                      _buildColumnHeader('FRAMEWORK'),
                      _buildColumnHeader('ARCHIVO'),
                    ],
                    rows: endpoints.asMap().entries.map((entry) {
                      final index = entry.key;
                      final ep = entry.value;
                      final isSelected = selected.contains(index);
                      final method = ep['method'] ?? 'GET';
                      final methodBadge = _methodBadgeColors(method);

                      return DataRow(
                        color: WidgetStateProperty.all(
                          index % 2 == 0
                              ? theme.colorScheme.primary.withOpacity(0.03)
                              : Colors.transparent,
                        ),
                        cells: [
                          DataCell(_buildCheckbox('endpoints', index, isSelected)),
                          DataCell(
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4),
                                color: methodBadge.$1,
                              ),
                              child: Text(
                                method,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: methodBadge.$2,
                                ),
                              ),
                            ),
                          ),
                          DataCell(_buildCodeText(ep['path'] ?? '')),
                          DataCell(
                            Text(
                              ep['framework'] ?? '—',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          DataCell(_buildFileText(ep['file'] ?? '')),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
      ),
    );
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
      backgroundColor: _glassSurfaceBackground(theme, lightOpacity: 0.45, darkOpacity: 0.28),
      child: Column(
        children: [
          _buildTableHeader('functions', functions.length, allSelected),
          if (functions.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se detectaron funciones',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (_isCompact(constraints)) {
                  return _buildMobileList(
                    itemCount: functions.length,
                    itemBuilder: (context, index) {
                      final fn = functions[index];
                      final isSelected = selected.contains(index);
                      final complexity = fn['complexity'] ?? 1;
                      final isAsync = fn['is_async'] ?? false;
                      final hasDoc = fn['docstring'] != null;

                      return _buildMobileCard(
                        isSelected: isSelected,
                        onCheckboxChanged: () => _toggleSelection('functions', index),
                        title: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isAsync)
                              Text(
                                'async ',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.secondary,
                                  fontFamily: 'JetBrains Mono',
                                ),
                              ),
                            Flexible(child: _buildCodeText(fn['name'] ?? '')),
                          ],
                        ),
                        rows: [
                          _mobileFieldRow('Archivo', fn['file'] ?? '—', isFile: true),
                          _mobileFieldRow(
                            'Parámetros',
                            (fn['params'] as List?)?.join(', ') ?? '—',
                          ),
                          _mobileFieldRow(
                            'Complejidad',
                            '$complexity',
                            valueColor: _complexityColor(_safeParseInt(complexity)),
                          ),
                        ],
                        trailing: hasDoc
                            ? Icon(Icons.check_circle, color: _docSuccessColor, size: 18)
                            : _buildSuggestionButton(fn['name'], fn['file'], fn['params'] ?? [], 'function'),
                      );
                    },
                  );
                }

                return _buildScrollableTable(
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowHeight: 40,
                    dataRowHeight: 48,
                    headingRowColor: WidgetStateProperty.all(
                      theme.colorScheme.primary.withOpacity(0.08),
                    ),
                    columns: [
                      const DataColumn(label: Text('')),
                      _buildColumnHeader('NOMBRE'),
                      _buildColumnHeader('ARCHIVO'),
                      _buildColumnHeader('PARÁMETROS'),
                      _buildColumnHeader('COMPLEJIDAD'),
                      _buildColumnHeader('DOCUMENTADA'),
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
                          DataCell(_buildCheckbox('functions', index, isSelected)),
                          DataCell(
                            Row(
                              children: [
                                if (isAsync)
                                  Text(
                                    'async ',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: theme.colorScheme.secondary,
                                      fontFamily: 'JetBrains Mono',
                                    ),
                                  ),
                                _buildCodeText(fn['name'] ?? ''),
                              ],
                            ),
                          ),
                          DataCell(_buildFileText(fn['file'] ?? '')),
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
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: _complexityColor(_safeParseInt(complexity)),
                              ),
                            ),
                          ),
                          DataCell(
                            hasDoc
                                ? Icon(Icons.check_circle, color: _docSuccessColor, size: 18)
                                : _buildSuggestionButton(fn['name'], fn['file'], fn['params'] ?? [], 'function'),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
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
      backgroundColor: _glassSurfaceBackground(theme, lightOpacity: 0.45, darkOpacity: 0.28),
      child: Column(
        children: [
          _buildTableHeader('classes', classes.length, allSelected),
          if (classes.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se detectaron clases',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (_isCompact(constraints)) {
                  return _buildMobileList(
                    itemCount: classes.length,
                    itemBuilder: (context, index) {
                      final cls = classes[index];
                      final isSelected = selected.contains(index);
                      final hasDoc = cls['docstring'] != null;

                      return _buildMobileCard(
                        isSelected: isSelected,
                        onCheckboxChanged: () => _toggleSelection('classes', index),
                        title: _buildCodeText(cls['name'] ?? ''),
                        rows: [
                          _mobileFieldRow('Archivo', cls['file'] ?? '—', isFile: true),
                          _mobileFieldRow(
                            'Métodos',
                            '${(cls['methods'] as List?)?.length ?? 0}',
                          ),
                          _mobileFieldRow(
                            'Bases',
                            (cls['bases'] as List?)?.join(', ') ?? '—',
                          ),
                        ],
                        trailing: hasDoc
                            ? Icon(Icons.check_circle, color: _docSuccessColor, size: 18)
                            : _buildSuggestionButton(cls['name'], cls['file'], [], 'class'),
                      );
                    },
                  );
                }

                return _buildScrollableTable(
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowHeight: 40,
                    dataRowHeight: 48,
                    headingRowColor: WidgetStateProperty.all(
                      theme.colorScheme.primary.withOpacity(0.08),
                    ),
                    columns: [
                      const DataColumn(label: Text('')),
                      _buildColumnHeader('CLASE'),
                      _buildColumnHeader('ARCHIVO'),
                      _buildColumnHeader('MÉTODOS'),
                      _buildColumnHeader('BASES'),
                      _buildColumnHeader('DOCUMENTADA'),
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
                          DataCell(_buildCheckbox('classes', index, isSelected)),
                          DataCell(_buildCodeText(cls['name'] ?? '')),
                          DataCell(_buildFileText(cls['file'] ?? '')),
                          DataCell(
                            Text(
                              '${(cls['methods'] as List?)?.length ?? 0}',
                              style: TextStyle(
                                fontSize: 12,
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
                                ? Icon(Icons.check_circle, color: _docSuccessColor, size: 18)
                                : _buildSuggestionButton(cls['name'], cls['file'], [], 'class'),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
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
      backgroundColor: _glassSurfaceBackground(theme, lightOpacity: 0.45, darkOpacity: 0.28),
      child: Column(
        children: [
          _buildTableHeader('structure', structure.length, allSelected),
          if (structure.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                'No se detectaron archivos',
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                if (_isCompact(constraints)) {
                  return _buildMobileList(
                    itemCount: structure.length,
                    itemBuilder: (context, index) {
                      final file = structure[index];
                      final isSelected = selected.contains(index);
                      final size = file['size'] ?? 0;
                      final sizeStr = size > 1024
                          ? '${(size / 1024).toStringAsFixed(1)} KB'
                          : '$size B';

                      return _buildMobileCard(
                        isSelected: isSelected,
                        onCheckboxChanged: () => _toggleSelection('structure', index),
                        title: _buildFileText(file['path'] ?? ''),
                        rows: [
                          _mobileFieldRow('Lenguaje', file['language'] ?? 'Desconocido'),
                          _mobileFieldRow(
                            'Tamaño',
                            sizeStr,
                            valueColor: _isDark
                                ? const Color(0xFFF87171)
                                : const Color(0xFFEF4444),
                          ),
                        ],
                      );
                    },
                  );
                }

                return _buildScrollableTable(
                  child: DataTable(
                    columnSpacing: 20,
                    headingRowHeight: 40,
                    dataRowHeight: 48,
                    headingRowColor: WidgetStateProperty.all(
                      theme.colorScheme.primary.withOpacity(0.08),
                    ),
                    columns: [
                      const DataColumn(label: Text('')),
                      _buildColumnHeader('RUTA'),
                      _buildColumnHeader('LENGUAJE'),
                      _buildColumnHeader('TAMAÑO'),
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
                          DataCell(_buildCheckbox('structure', index, isSelected)),
                          DataCell(_buildFileText(file['path'] ?? '')),
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
                                fontSize: 12,
                                color: _isDark
                                    ? const Color(0xFFF87171)
                                    : const Color(0xFFEF4444),
                                fontFamily: 'JetBrains Mono',
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // ============================================================
  // HELPERS DE TABLA
  // ============================================================

  Widget _buildTableHeader(String type, int count, bool allSelected) {
    final theme = Theme.of(context);
    final labels = {
      'endpoints': 'endpoints',
      'functions': 'funciones',
      'classes': 'clases',
      'structure': 'archivos',
    };

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Checkbox(
            value: allSelected,
            onChanged: (v) => _toggleSelectAll(type, v),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            visualDensity: VisualDensity.compact,
            checkColor: Colors.white,
            activeColor: theme.colorScheme.primary,
            side: BorderSide(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'Seleccionar todos',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          Text(
            '$count ${labels[type]}',
            style: TextStyle(
              fontSize: 11,
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'JetBrains Mono',
            ),
          ),
          const SizedBox(width: 12),
          InkWell(
            onTap: _saveSelections,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: theme.colorScheme.primary,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.save, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Guardar',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // RESPONSIVIDAD: TABLA VS. LISTA DE TARJETAS EN MÓVIL
  // ============================================================

  // Debajo de este ancho mostramos tarjetas apiladas en vez de la tabla,
  // porque un DataTable con varias columnas no cabe en una pantalla de celular.
  bool _isCompact(BoxConstraints constraints) => constraints.maxWidth < 640;

  // En pantallas anchas conservamos el DataTable pero con un Scrollbar
  // siempre visible y arrastrable, para que quede claro que se puede
  // desplazar horizontalmente (además del gesto de swipe).
  Widget _buildScrollableTable({required Widget child}) {
    final scrollController = ScrollController();
    return Scrollbar(
      controller: scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        controller: scrollController,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.only(bottom: 8),
        child: child,
      ),
    );
  }

  Widget _buildMobileList({
    required int itemCount,
    required Widget Function(BuildContext, int) itemBuilder,
  }) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      itemCount: itemCount,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: itemBuilder,
    );
  }

  // Tarjeta genérica para representar una "fila" de la tabla en pantallas
  // angostas: checkbox + título arriba, pares clave/valor debajo.
  Widget _buildMobileCard({
    required bool isSelected,
    required VoidCallback onCheckboxChanged,
    required Widget title,
    required List<Widget> rows,
    Widget? topRight,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isSelected
            ? theme.colorScheme.primary.withOpacity(0.06)
            : theme.colorScheme.primary.withOpacity(0.03),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Transform.translate(
                offset: const Offset(-8, -8),
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: Checkbox(
                    value: isSelected,
                    onChanged: (_) => onCheckboxChanged(),
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    visualDensity: VisualDensity.compact,
                    checkColor: Colors.white,
                    activeColor: theme.colorScheme.primary,
                    side: BorderSide(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(child: title),
              if (topRight != null) ...[
                const SizedBox(width: 8),
                topRight,
              ],
            ],
          ),
          const SizedBox(height: 6),
          ...rows,
          if (trailing != null) ...[
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: trailing),
          ],
        ],
      ),
    );
  }

  // Fila clave/valor usada dentro de _buildMobileCard. `isFile` aplica el
  // mismo estilo monoespaciado que usa la columna ARCHIVO en la tabla.
  Widget _mobileFieldRow(String label, String value, {bool isFile = false, Color? valueColor}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
                letterSpacing: 0.3,
              ),
            ),
          ),
          Expanded(
            child: isFile
                ? _buildFileText(value)
                : Text(
                    value,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: valueColor != null ? FontWeight.bold : FontWeight.normal,
                      color: valueColor ?? theme.colorScheme.onSurface,
                      fontFamily: valueColor != null ? 'JetBrains Mono' : null,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  // ⬇️ CORRECCIÓN: Ahora devuelve DataColumn en lugar de Widget
  DataColumn _buildColumnHeader(String text) {
    final theme = Theme.of(context);
    return DataColumn(
      label: Text(
        text,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildCheckbox(String type, int index, bool isSelected) {
    final theme = Theme.of(context);
    return Checkbox(
      value: isSelected,
      onChanged: (_) => _toggleSelection(type, index),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      visualDensity: VisualDensity.compact,
      checkColor: Colors.white,
      activeColor: theme.colorScheme.primary,
      side: BorderSide(
        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
      ),
    );
  }

  Widget _buildCodeText(String text) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: theme.colorScheme.primary.withOpacity(0.05),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          color: theme.colorScheme.primary,
          fontFamily: 'JetBrains Mono',
        ),
      ),
    );
  }

  Widget _buildFileText(String text) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 12,
        color: _isDark ? const Color(0xFF2DD4BF) : const Color(0xFF0D9488),
        fontFamily: 'JetBrains Mono',
      ),
    );
  }

  Widget _buildSuggestionButton(String name, String file, List params, String kind) {
    final suggestFg = _isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309);
    final suggestBg = _isDark
        ? const Color(0xFFFBBF24).withOpacity(0.1)
        : const Color(0xFFFBBF24).withOpacity(0.12);
    final suggestBorder = _isDark
        ? const Color(0xFFFBBF24).withOpacity(0.3)
        : const Color(0xFFFBBF24).withOpacity(0.35);

    return InkWell(
      onTap: () => _showSuggestionModal(name, file, params.join(', '), kind),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: suggestBg,
          border: Border.all(color: suggestBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lightbulb, size: 13, color: suggestFg),
            const SizedBox(width: 4),
            Text(
              'Sugerencia',
              style: TextStyle(
                fontSize: 9,
                color: suggestFg,
                fontFamily: 'JetBrains Mono',
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // MODAL DE SUGERENCIA
  // ============================================================

  void _showSuggestionModal(String name, String file, String params, String kind) {
    showDialog(
      context: context,
      builder: (context) => _SuggestionDialog(
        name: name,
        file: file,
        params: params,
        kind: kind,
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

    final backgroundPaint = Paint()
      ..color = isDark ? Colors.white.withOpacity(0.1) : Colors.grey.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    canvas.drawCircle(center, radius, backgroundPaint);

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
// MODAL DE COLABORADORES (BOTTOM SHEET)
// ============================================================

class _ContributorsModal extends StatelessWidget {
  final List<Map<String, dynamic>> contributors;
  final bool isLoading;
  final Future<void> Function() onRefresh;

  const _ContributorsModal({
    required this.contributors,
    required this.isLoading,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalCommits = contributors.fold<int>(
      0,
      (sum, c) => sum + (c['commits'] as int? ?? 0),
    );

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.2),
            ),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(2),
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: theme.colorScheme.secondary.withOpacity(0.15),
                        border: Border.all(
                          color: theme.colorScheme.secondary.withOpacity(0.3),
                        ),
                      ),
                      child: Icon(
                        Icons.group,
                        color: theme.colorScheme.secondary,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Colaboradores',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            '${contributors.length} colaborador${contributors.length != 1 ? 'es' : ''} · $totalCommits commits',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              Expanded(
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : contributors.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.group_off,
                                  size: 48,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  'Sin colaboradores',
                                  style: TextStyle(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                            itemCount: contributors.length,
                            itemBuilder: (context, index) {
                              final c = contributors[index];
                              return _buildContributorItem(context, index, c, totalCommits);
                            },
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildContributorItem(
    BuildContext context,
    int index,
    Map<String, dynamic> c,
    int totalCommits,
  ) {
    final theme = Theme.of(context);
    final name = c['name']?.toString() ?? 'Desconocido';
    final email = c['email']?.toString() ?? '';
    final commits = c['commits'] as int? ?? 0;
    final role = c['role']?.toString() ?? '';
    final maxCommits = contributors.isNotEmpty
        ? (contributors.first['commits'] as int? ?? 1)
        : 1;
    final barWidth = maxCommits > 0 ? (commits / maxCommits).clamp(0.0, 1.0) : 0.0;
    final pct = totalCommits > 0 ? (commits / totalCommits * 100) : 0.0;

    final colors = [
      Colors.blue.shade400,
      Colors.indigo.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.red.shade400,
      Colors.pink.shade400,
      Colors.purple.shade400,
      Colors.teal.shade400,
    ];
    final color = colors[index % colors.length];

    final initials = name
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join()
        .toUpperCase();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: index % 2 == 0
            ? theme.colorScheme.primary.withOpacity(0.04)
            : Colors.transparent,
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withOpacity(0.1),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
            child: Center(
              child: Text(
                initials,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          color: theme.colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (role == 'admin')
                      _buildRoleChip('Admin', theme.colorScheme.primary),
                    if (role == 'owner')
                      _buildRoleChip('Owner', theme.colorScheme.secondary),
                  ],
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: barWidth,
                          backgroundColor: theme.colorScheme.outlineVariant.withOpacity(0.2),
                          color: color,
                          minHeight: 5,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$commits · ${pct.toStringAsFixed(1)}%',
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'JetBrains Mono',
                        color: theme.colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoleChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      margin: const EdgeInsets.only(left: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

// ============================================================
// DIALOG DE SUGERENCIA
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
              style: TextStyle(
                fontSize: 11,
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
                          CircularProgressIndicator(color: theme.colorScheme.primary),
                          const SizedBox(height: 12),
                          Text(
                            'Generando sugerencia con IA...',
                            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
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
                                style: TextStyle(color: theme.colorScheme.error),
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
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Expanded(
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(16),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: theme.brightness == Brightness.dark
                                      ? AppColors.codeBlockBackgroundDark
                                      : AppColors.codeBlockBackground,
                                  border: Border.all(
                                    color: theme.colorScheme.primary.withOpacity(0.15),
                                  ),
                                ),
                                child: SingleChildScrollView(
                                  child: Text(
                                    _suggestion!,
                                    style: const TextStyle(
                                      fontFamily: 'JetBrains Mono',
                                      fontSize: 12,
                                      height: 1.6,
                                      color: AppColors.codeBlockForeground,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            GradientButton(
                              onPressed: () {},
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