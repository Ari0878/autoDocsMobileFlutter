import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'dart:async';
import 'dart:math';
import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';

class AnalisisScreen extends StatefulWidget {
  const AnalisisScreen({super.key});

  @override
  State<AnalisisScreen> createState() => _AnalisisScreenState();
}

class _AnalisisScreenState extends State<AnalisisScreen> {
  final ApiService _api = ApiService();
  List<Project> _projects = [];
  bool _isLoading = true;
  String? _error;

  // KPIs
  int _totalProjects = 0;
  int _completedProjects = 0;
  double _averageQuality = 0;
  int _totalFunctions = 0;

  // Datos para gráficos
  List<String> _qualityLabels = [];
  List<double> _qualityValues = [];
  List<Color> _qualityColors = [];

  // Estado (para gráfico de dona)
  Map<String, int> _statusMap = {};
  List<Color> _statusColors = [];
  List<String> _statusLabels = [];

  // Lenguajes
  Map<String, int> _languageMap = {};

  // Tendencia de calidad
  String _qualityTrend = '';
  Color _qualityTrendColor = Colors.green;
  IconData _qualityTrendIcon = Icons.arrow_upward;
  String _bestProjectName = '';
  int _bestProjectScore = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final authProvider = context.read<AuthProvider>();
      if (authProvider.token == null) {
        setState(() {
          _error = 'No hay sesión activa';
          _isLoading = false;
        });
        return;
      }

      final response = await _api.get('/api/projects/');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        _projects = data.map((p) => Project.fromJson(p)).toList();
        _processData();
        setState(() {
          _isLoading = false;
        });
      } else {
        setState(() {
          _error = 'Error al cargar datos: ${response.statusCode}';
          _isLoading = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión: $e';
        _isLoading = false;
      });
    }
  }

  void _processData() {
    // KPIs
    _totalProjects = _projects.length;
    final completed = _projects.where((p) => p.isCompleted).toList();
    _completedProjects = completed.length;

    final scores = completed
        .map((p) => p.stats?.qualityScore ?? 0)
        .where((s) => s > 0)
        .toList();
    _averageQuality = scores.isNotEmpty
        ? scores.reduce((a, b) => a + b) / scores.length
        : 0;

    _totalFunctions = _projects.fold(
      0,
      (sum, p) => sum + (p.stats?.functions ?? 0),
    );

    // Calidad por proyecto
    final sortedCompleted = List<Project>.from(completed)
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));

    _qualityLabels = sortedCompleted.map((p) => p.name).toList();
    _qualityValues = sortedCompleted
        .map((p) => (p.stats?.qualityScore ?? 0).toDouble())
        .toList();

    _qualityColors = _qualityValues.map((v) {
      if (v >= 70) return Colors.green.shade400;
      if (v >= 40) return Colors.orange.shade400;
      return Colors.red.shade400;
    }).toList();

    // Tendencia
    if (_qualityValues.length >= 2) {
      final diff = _qualityValues.last - _qualityValues.first;
      if (diff > 0) {
        _qualityTrend = '+${diff.round()} pts';
        _qualityTrendColor = Colors.green;
        _qualityTrendIcon = Icons.arrow_upward;
      } else if (diff < 0) {
        _qualityTrend = '${diff.round()} pts';
        _qualityTrendColor = Colors.red;
        _qualityTrendIcon = Icons.arrow_downward;
      } else {
        _qualityTrend = 'Sin cambio';
        _qualityTrendColor = Colors.orange;
        _qualityTrendIcon = Icons.remove;
      }

      if (_qualityValues.isNotEmpty) {
        final bestIndex = _qualityValues.indexOf(_qualityValues.reduce((a, b) => a > b ? a : b));
        _bestProjectName = _qualityLabels[bestIndex];
        _bestProjectScore = _qualityValues[bestIndex].round();
      }
    }

    // Estado (para gráfico de dona)
    _statusMap = {};
    for (final p in _projects) {
      final key = p.isCompleted ? 'Completado' :
                  p.isAnalyzing ? 'Analizando' :
                  p.hasError ? 'Error' : 'Pendiente';
      _statusMap[key] = (_statusMap[key] ?? 0) + 1;
    }

    // Quitar estados con valor 0
    _statusMap.removeWhere((key, value) => value == 0);
    _statusLabels = _statusMap.keys.toList();

    final statusColorMap = {
      'Completado': Colors.green.shade400,
      'Pendiente': Colors.grey.shade500,
      'Analizando': Colors.orange.shade400,
      'Error': Colors.red.shade400,
    };
    _statusColors = _statusLabels
        .map((key) => statusColorMap[key] ?? Colors.blue.shade400)
        .toList();

    // Lenguajes
    _languageMap = {};
    for (final p in _projects) {
      final lang = (p.language != null && p.language != 'unknown')
          ? p.language!
          : 'Otro';
      _languageMap[lang] = (_languageMap[lang] ?? 0) + 1;
    }

    // Ordenar lenguajes
    final sortedEntries = _languageMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    _languageMap = Map.fromEntries(sortedEntries);
  }

  Color _getLanguageColor(String lang) {
    final colors = {
      'Python': const Color(0xFF38BDF8),
      'JavaScript': const Color(0xFFF7DF1E),
      'TypeScript': const Color(0xFF3178C6),
      'PHP': const Color(0xFF777BB4),
      'Ruby': const Color(0xFFCC342D),
      'Go': const Color(0xFF00ADD8),
      'Rust': const Color(0xFFDEA584),
      'C++': const Color(0xFFF34B7D),
      'Java': const Color(0xFFB07219),
      'Dart': const Color(0xFF00B4AB),
      'HTML': const Color(0xFFE34C26),
      'CSS': const Color(0xFF563D7C),
      'Shell': const Color(0xFF89E051),
      'SQL': const Color(0xFFE38C00),
      'Otro': const Color(0xFF94A3B8),
    };
    return colors[lang] ?? const Color(0xFF94A3B8);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: theme.colorScheme.error,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: theme.colorScheme.error),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _loadData,
                        child: const Text('Reintentar'),
                      ),
                    ],
                  ),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Header
                      _buildHeader(theme, isDark),
                      const SizedBox(height: 20),

                      // KPIs
                      _buildKPIs(theme),
                      const SizedBox(height: 20),

                      // Gráfico de Calidad por proyecto (Barras horizontales)
                      _buildQualityBarChart(theme, isDark),
                      const SizedBox(height: 20),

                      // Gráfico de Estado (Dona)
                      _buildStatusDoughnutChart(theme, isDark),
                      const SizedBox(height: 20),

                      // Lenguajes
                      _buildLanguagesCard(theme, isDark),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(ThemeData theme, bool isDark) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Análisis',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 28,
                foreground: Paint()
                  ..shader = LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.primary.withOpacity(0.6),
                    ],
                  ).createShader(const Rect.fromLTWH(0, 0, 200, 40)),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Resumen de tus proyectos',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
        // Badge de tendencia
        if (_qualityTrend.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              color: _qualityTrendColor.withOpacity(0.12),
              border: Border.all(color: _qualityTrendColor.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_qualityTrendIcon, size: 14, color: _qualityTrendColor),
                const SizedBox(width: 4),
                Text(
                  _qualityTrend,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _qualityTrendColor,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  // ============================================================
  // KPIs
  // ============================================================

  Widget _buildKPIs(ThemeData theme) {
    final kpis = [
      {'value': '$_totalProjects', 'label': 'Proyectos totales', 'icon': Icons.folder},
      {'value': '$_completedProjects', 'label': 'Completados', 'icon': Icons.check_circle},
      {'value': _averageQuality > 0 ? '${_averageQuality.round()}/100' : '—', 'label': 'Calidad promedio', 'icon': Icons.star},
      {'value': _totalFunctions > 0 ? '$_totalFunctions' : '—', 'label': 'Funciones totales', 'icon': Icons.functions},
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.5,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: kpis.length,
      itemBuilder: (ctx, index) {
        final kpi = kpis[index];
        return GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                kpi['icon'] as IconData,
                color: theme.colorScheme.primary.withOpacity(0.6),
                size: 20,
              ),
              const SizedBox(height: 6),
              Text(
                kpi['value'] as String,
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 26,
                ),
              ),
              Text(
                kpi['label'] as String,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // GRÁFICO DE CALIDAD POR PROYECTO (BARRAS HORIZONTALES)
  // ============================================================

  Widget _buildQualityBarChart(ThemeData theme, bool isDark) {
    final hasData = _qualityValues.isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.bar_chart,
                color: Colors.green.shade400.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Calidad por proyecto',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 0.3,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Leyenda
          Row(
            children: [
              _buildLegendDot(Colors.green.shade400),
              const Text(' >= 70', style: TextStyle(fontSize: 10)),
              const SizedBox(width: 12),
              _buildLegendDot(Colors.orange.shade400),
              const Text(' >= 40', style: TextStyle(fontSize: 10)),
              const SizedBox(width: 12),
              _buildLegendDot(Colors.red.shade400),
              const Text(' < 40', style: TextStyle(fontSize: 10)),
              const SizedBox(width: 12),
              Text(
                '(Puntos de calidad)',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          if (hasData)
            SizedBox(
              height: 180,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: 100,
                  barTouchData: BarTouchData(
                    enabled: true,
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipColor: (group) => isDark ? Colors.grey[800]! : Colors.white,
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        return BarTooltipItem(
                          '${_qualityLabels[groupIndex]}\n${rod.toY.round()}/100',
                          TextStyle(
                            color: isDark ? Colors.white : Colors.black,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      },
                    ),
                  ),
                  titlesData: FlTitlesData(
                    show: true,
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          final index = value.toInt();
                          if (index < 0 || index >= _qualityLabels.length) {
                            return const Text('');
                          }
                          final label = _qualityLabels[index];
                          return Text(
                            label.length > 6 ? '${label.substring(0, 5)}…' : label,
                            style: TextStyle(
                              fontSize: 8,
                              color: isDark ? Colors.white70 : Colors.black54,
                            ),
                          );
                        },
                        reservedSize: 30,
                      ),
                    ),
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (value, meta) {
                          if (value % 20 == 0) {
                            return Text(
                              '${value.toInt()}',
                              style: TextStyle(
                                fontSize: 9,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        },
                        reservedSize: 28,
                      ),
                    ),
                    topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                    rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    drawVerticalLine: false,
                    horizontalInterval: 20,
                    getDrawingHorizontalLine: (value) {
                      return FlLine(
                        color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                        strokeWidth: 0.5,
                      );
                    },
                  ),
                  barGroups: _qualityValues.asMap().entries.map((entry) {
                    final index = entry.key;
                    final value = entry.value;
                    final color = _qualityColors[index];

                    return BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: value,
                          color: color,
                          width: 16,
                          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                          backDrawRodData: BackgroundBarChartRodData(
                            show: true,
                            toY: 100,
                            color: isDark ? Colors.white.withOpacity(0.05) : Colors.black.withOpacity(0.05),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
              ),
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No hay proyectos completados',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                ),
              ),
            ),

          if (hasData && _bestProjectName.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Mejor proyecto: $_bestProjectName ($_bestProjectScore/100)',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                fontSize: 10,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildLegendDot(Color color) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: color,
      ),
    );
  }

  // ============================================================
  // GRÁFICO DE ESTADO (DONA / PASTEL)
  // ============================================================

  Widget _buildStatusDoughnutChart(ThemeData theme, bool isDark) {
    final hasData = _statusMap.isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.donut_small,
                color: theme.colorScheme.secondary.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Estado de proyectos',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 0.3,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Distribución actual de tus proyectos',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 16),

          if (hasData)
            Row(
              children: [
                // Gráfico de dona
                SizedBox(
                  height: 160,
                  width: 160,
                  child: PieChart(
                    PieChartData(
                      sections: _statusMap.entries.map((entry) {
                        final index = _statusLabels.indexOf(entry.key);
                        final color = _statusColors[index];
                        final total = _statusMap.values.fold(0, (s, v) => s + v);
                        final percentage = (entry.value / total * 100);

                        return PieChartSectionData(
                          value: entry.value.toDouble(),
                          title: '${percentage.toStringAsFixed(1)}%',
                          color: color,
                          radius: 60,
                          titleStyle: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            shadows: [
                              Shadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                              ),
                            ],
                          ),
                          badgeWidget: Text(
                            '${entry.value}',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                          badgePositionPercentageOffset: .98,
                        );
                      }).toList(),
                      sectionsSpace: 2,
                      centerSpaceRadius: 40,
                      startDegreeOffset: -90,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // Leyenda
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: _statusMap.entries.map((entry) {
                      final index = _statusLabels.indexOf(entry.key);
                      final color = _statusColors[index];
                      final total = _statusMap.values.fold(0, (s, v) => s + v);
                      final percentage = (entry.value / total * 100);

                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 3),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: color,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                entry.key,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDark ? Colors.white70 : Colors.black87,
                                ),
                              ),
                            ),
                            Text(
                              '${entry.value} (${percentage.toStringAsFixed(1)}%)',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isDark ? Colors.white60 : Colors.black54,
                              ),
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            )
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No hay proyectos',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // LENGUAJES
  // ============================================================

  Widget _buildLanguagesCard(ThemeData theme, bool isDark) {
    final hasData = _languageMap.isNotEmpty;

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.code,
                color: theme.colorScheme.primary.withOpacity(0.7),
                size: 20,
              ),
              const SizedBox(width: 8),
              Text(
                'Lenguajes usados',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 10,
                  letterSpacing: 0.3,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Cantidad de proyectos por lenguaje',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              fontSize: 10,
            ),
          ),
          const SizedBox(height: 12),

          if (hasData)
            ..._languageMap.entries.map((entry) {
              final lang = entry.key;
              final count = entry.value;
              final total = _languageMap.values.fold(0, (s, v) => s + v);
              final percentage = (count / total * 100);
              final maxCount = _languageMap.values.first;
              final barWidth = (count / maxCount * 100).clamp(0.0, 100.0);
              final color = _getLanguageColor(lang);

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    Container(
                      width: 60,
                      height: 10,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(3),
                        color: color,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: barWidth / 100,
                          backgroundColor: isDark
                              ? Colors.white.withOpacity(0.05)
                              : Colors.black.withOpacity(0.05),
                          color: color,
                          minHeight: 10,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$count (${percentage.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontSize: 9,
                        color: isDark ? Colors.white70 : Colors.black54,
                        fontFamily: 'JetBrains Mono',
                      ),
                    ),
                  ],
                ),
              );
            })
          else
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Text(
                  'No hay lenguajes detectados',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  ),
                ),
              ),
            ),

          const SizedBox(height: 8),
          Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.1)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total: ${_languageMap.length} lenguajes · ${_projects.length} proyectos',
                style: TextStyle(
                  fontSize: 10,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
              if (_languageMap.isNotEmpty)
                Text(
                  'Más usado: ${_languageMap.keys.first} (${_languageMap.values.first} proyecto${_languageMap.values.first != 1 ? 's' : ''})',
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.white60 : Colors.black54,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}