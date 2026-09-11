import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/project_card.dart';
import '../utils/constants.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  List<Project> _projects = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  Timer? _refreshTimer;
  final ApiService _api = ApiService();

  @override
  void initState() {
    super.initState();
    _loadDashboardData();
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _loadProjects(showLoading: false);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  // Cargar datos del dashboard (usuario + proyectos)
  Future<void> _loadDashboardData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // 1. Refrescar usuario para obtener el plan actualizado
      final authProvider = context.read<AuthProvider>();
      await authProvider.refreshUser();
      
      // 2. Cargar proyectos
      await _loadProjects(showLoading: false);
      
      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error al cargar datos';
      });
    }
  }

  Future<void> _loadProjects({bool showLoading = true}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _error = null;
      });
    } else {
      setState(() => _isRefreshing = true);
    }

    try {
      final response = await _api.get('/api/projects/');

      if (response.statusCode == 200) {
        final List<dynamic> data = response.data;
        final projects = data.map((p) => Project.fromJson(p)).toList();

        setState(() {
          _projects = projects;
          _isLoading = false;
          _isRefreshing = false;
          _error = null;
        });
      } else {
        setState(() {
          _error = 'Error al cargar proyectos';
          _isLoading = false;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión';
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  // ============================================================
  // ESTADÍSTICAS
  // ============================================================
  
  int get _totalProjects => _projects.length;
  int get _completedProjects => _projects.where((p) => p.isCompleted).length;
  int get _activeProjects => _projects.where((p) => !p.isCompleted).length;
  int get _totalFunctions => _projects.fold(0, (sum, p) => sum + (p.stats?.functions ?? 0));
  int get _totalEndpoints => _projects.fold(0, (sum, p) => sum + (p.stats?.endpoints ?? 0));
  double get _progressPercent => _totalProjects > 0 ? (_completedProjects / _totalProjects) * 100 : 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = context.watch<ThemeProvider>().isDark;
    final authProvider = context.watch<AuthProvider>();
    final user = authProvider.user;
    final plan = user?.plan ?? 'free';

    // Log para debug - muestra el plan actual
    print('📊 [Dashboard] Plan del usuario: $plan, Proyectos: $_totalProjects');

    final limits = {'free': 3, 'pro': 20, 'enterprise': -1};
    final limit = limits[plan] ?? 3;
    final canCreate = limit == -1 || _totalProjects < limit;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Recargar datos del usuario y proyectos
            await authProvider.refreshUser();
            await _loadProjects(showLoading: true);
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(
              top: 12,
              left: 16,
              right: 16,
              bottom: 16,
            ),
            physics: const AlwaysScrollableScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // HEADER
                _buildHeader(context, user, plan, canCreate, limit, isDark),
                const SizedBox(height: 14),

                // STATS CARDS
                _buildStatsGrid(context),
                const SizedBox(height: 14),

                // PROGRESS CARD
                _buildProgressCard(context),
                const SizedBox(height: 14),

                // RECENT PROJECTS
                _buildRecentProjects(context),
                const SizedBox(height: 80),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  
  Widget _buildHeader(BuildContext context, user, String plan, bool canCreate, int limit, bool isDark) {
    final theme = Theme.of(context);

    final planNames = {
      'free': 'Free',
      'pro': 'Pro',
      'enterprise': 'Enterprise',
    };

    final planColors = {
      'free': theme.colorScheme.onSurfaceVariant,
      'pro': theme.colorScheme.primary,
      'enterprise': const Color(0xFFF59E0B), // Ámbar
    };

    final planIcons = {
      'free': Icons.workspace_premium,
      'pro': Icons.star,
      'enterprise': Icons.workspace_premium,
    };

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Dashboard',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                  color: theme.colorScheme.onSurface,
                ),
              ),
              Text(
                'Bienvenido, ${user?.name ?? 'Usuario'}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Theme toggle
            IconButton(
              onPressed: _toggleTheme,
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                padding: const EdgeInsets.all(6),
                minimumSize: const Size(32, 32),
              ),
            ),
            const SizedBox(width: 4),
            // Plan badge - con color dinámico según el plan
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: (planColors[plan] ?? theme.colorScheme.primary).withOpacity(0.15),
                border: Border.all(
                  color: (planColors[plan] ?? theme.colorScheme.primary).withOpacity(0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    planIcons[plan] ?? Icons.workspace_premium,
                    size: 11,
                    color: planColors[plan] ?? theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 2),
                  Text(
                    planNames[plan] ?? 'Free',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: planColors[plan] ?? theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Container(
                    width: 1,
                    height: 10,
                    color: theme.colorScheme.onSurfaceVariant.withOpacity(0.3),
                  ),
                  const SizedBox(width: 3),
                  Text(
                    '$_totalProjects${limit == -1 ? '/∞' : '/$limit'}',
                    style: TextStyle(
                      fontSize: 8,
                      fontWeight: FontWeight.w600,
                      color: _totalProjects >= limit && limit != -1
                          ? Colors.red
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            // New project button - deshabilitado si no puede crear
            GradientButton(
              onPressed: canCreate
                  ? () => _showCreateProjectDialog(context)
                  : () => _showLimitDialog(context, plan, limit),
              text: 'Nuevo',
              icon: Icons.add,
              width: 68,
              height: 30,
              fontSize: 10,
              isOutlined: !canCreate,
            ),
          ],
        ),
      ],
    );
  }

  void _toggleTheme() {
    final themeProvider = context.read<ThemeProvider>();
    themeProvider.toggleTheme();
  }

  // ============================================================
  // STATS GRID
  // ============================================================
  
  Widget _buildStatsGrid(BuildContext context) {
    final theme = Theme.of(context);

    final stats = [
      {
        'label': 'Proyectos', 
        'value': _totalProjects, 
        'icon': Icons.description, 
        'color': theme.colorScheme.primary,
        'iconBg': theme.colorScheme.primary.withOpacity(0.12),
      },
      {
        'label': 'Completados', 
        'value': _completedProjects, 
        'icon': Icons.check_circle, 
        'color': Colors.green.shade400,
        'iconBg': Colors.green.shade400.withOpacity(0.12),
      },
      {
        'label': 'Funciones', 
        'value': _totalFunctions, 
        'icon': Icons.functions, 
        'color': theme.colorScheme.secondary,
        'iconBg': theme.colorScheme.secondary.withOpacity(0.12),
      },
      {
        'label': 'Endpoints', 
        'value': _totalEndpoints, 
        'icon': Icons.api, 
        'color': theme.colorScheme.primary,
        'iconBg': theme.colorScheme.primary.withOpacity(0.12),
      },
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.6,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
      ),
      itemCount: stats.length,
      itemBuilder: (ctx, index) {
        final stat = stats[index];
        return GlassCard(
          padding: const EdgeInsets.all(12),
          backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: stat['iconBg'] as Color,
                ),
                child: Icon(
                  stat['icon'] as IconData,
                  color: stat['color'] as Color,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${stat['value']}',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        height: 1.1,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      stat['label'] as String,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // PROGRESS CARD
  // ============================================================
  
  Widget _buildProgressCard(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(14),
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            height: 50,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomPaint(
                  size: const Size(50, 50),
                  painter: ProgressRingPainter(
                    progress: _progressPercent / 100,
                    color: theme.colorScheme.primary,
                    isDark: theme.brightness == Brightness.dark,
                  ),
                ),
                Text(
                  '${_progressPercent.round()}%',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _totalProjects == 0
                      ? 'Sin proyectos'
                      : _completedProjects == _totalProjects
                          ? 'Todo completado 🎉'
                          : '${_completedProjects} de ${_totalProjects} completados',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Proyectos finalizados sobre el total',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    _buildBadge('Completados: $_completedProjects', Colors.green),
                    _buildBadge('Activos: $_activeProjects', theme.colorScheme.primary),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 7,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ============================================================
  // RECENT PROJECTS
  // ============================================================
  
  Widget _buildRecentProjects(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Proyectos Recientes',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 15,
                color: theme.colorScheme.onSurface,
              ),
            ),
            TextButton(
              onPressed: () => Navigator.pushNamed(context, '/projects'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'Ver todos',
                style: TextStyle(
                  fontSize: 9,
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoading)
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: CircularProgressIndicator(
                color: theme.colorScheme.primary,
              ),
            ),
          )
        else if (_error != null)
          Center(
            child: Column(
              children: [
                Icon(Icons.error_outline, color: theme.colorScheme.error, size: 32),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () => _loadProjects(showLoading: true),
                  child: const Text('Reintentar'),
                ),
              ],
            ),
          )
        else if (_projects.isEmpty)
          _buildEmptyState(context)
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.8,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
            ),
            itemCount: _projects.length > 6 ? 6 : _projects.length,
            itemBuilder: (ctx, index) {
              final project = _projects[index];
              return ProjectCard(
                project: project,
                onTap: () => Navigator.pushNamed(
                  context,
                  '/project',
                  arguments: project.id,
                ),
                onEdit: () => _showEditProjectDialog(context, project),
                showSync: project.githubUrl != null,
                onSync: () => _syncProject(context, project),
              );
            },
          ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);

    return GlassCard(
      padding: const EdgeInsets.all(32),
      backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
      child: Column(
        children: [
          Icon(
            Icons.folder_open,
            size: 40,
            color: theme.colorScheme.primary.withOpacity(0.5),
          ),
          const SizedBox(height: 10),
          Text(
            'Sin proyectos aún',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 15,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Sube tu primer proyecto para comenzar',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 10),
          GradientButton(
            onPressed: () => _showCreateProjectDialog(context),
            text: 'Crear proyecto',
            width: 130,
            height: 34,
            fontSize: 11,
          ),
        ],
      ),
    );
  }

  // ============================================================
  // DIALOGOS
  // ============================================================

  void _showCreateProjectDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _CreateProjectDialog(),
    ).then((_) => _loadProjects(showLoading: true));
  }

  void _showEditProjectDialog(BuildContext context, Project project) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditProjectDialog(project: project),
    ).then((_) => _loadProjects(showLoading: true));
  }

  void _showLimitDialog(BuildContext context, String plan, int limit) {
    final theme = Theme.of(context);
    
    final planNames = {
      'free': 'Gratuito (3 proyectos)',
      'pro': 'Pro (20 proyectos)',
      'enterprise': 'Enterprise (Ilimitado)',
    };

    final planColors = {
      'free': theme.colorScheme.onSurfaceVariant,
      'pro': theme.colorScheme.primary,
      'enterprise': const Color(0xFFF59E0B),
    };

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Límite alcanzado'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 12),
            Text(
              'Has alcanzado el límite de $_totalProjects proyectos para tu plan actual.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                color: (planColors[plan] ?? theme.colorScheme.primary).withOpacity(0.1),
                border: Border.all(
                  color: (planColors[plan] ?? theme.colorScheme.primary).withOpacity(0.2),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    plan == 'pro' ? Icons.star : Icons.workspace_premium,
                    size: 14,
                    color: planColors[plan] ?? theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Plan actual: ${planNames[plan] ?? 'Gratuito'}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: planColors[plan] ?? theme.colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              plan == 'free' 
                  ? 'Actualiza al plan Pro para crear hasta 20 proyectos y acceder a más funciones.'
                  : plan == 'pro'
                      ? 'Actualiza al plan Enterprise para proyectos ilimitados y soporte prioritario.'
                      : 'Contacta a soporte para aumentar tu límite de proyectos.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          if (plan != 'enterprise')
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/pricing');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Ver planes'),
            ),
        ],
      ),
    );
  }

  Future<void> _syncProject(BuildContext context, Project project) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Actualizar proyecto'),
        content: Text(
          '¿Actualizar "${project.name}" desde GitHub?\nEsto reemplazará los datos actuales.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Actualizar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await _api.post('/api/projects/${project.id}/sync');

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proyecto sincronizado correctamente'),
              backgroundColor: Colors.green,
            ),
          );
          _loadProjects(showLoading: true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al sincronizar'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${ApiService.errorMessage(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

// ============================================================
// PROGRESS RING PAINTER
// ============================================================

class ProgressRingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final bool isDark;

  const ProgressRingPainter({
    required this.progress,
    required this.color,
    this.isDark = false,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 3;
    final strokeWidth = 3.5;

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
           oldDelegate.isDark != isDark;
  }
}

// ============================================================
// CREATE PROJECT DIALOG
// ============================================================

class _CreateProjectDialog extends StatefulWidget {
  const _CreateProjectDialog();

  @override
  State<_CreateProjectDialog> createState() => _CreateProjectDialogState();
}

class _CreateProjectDialogState extends State<_CreateProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _githubController = TextEditingController();
  final ApiService _api = ApiService();
  bool _isLoading = false;
  PlatformFile? _selectedFile;
  String? get _selectedFileName => _selectedFile?.name;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _githubController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    if (_isLoading) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
        withData: true,
      );
      if (!mounted || result == null) return;
      final file = result.files.single;
      if (!file.name.toLowerCase().endsWith('.zip') ||
          file.bytes == null || file.bytes!.isEmpty) {
        throw const FormatException('Selecciona un archivo ZIP válido y no vacío.');
      }
      setState(() {
        _selectedFile = file;
        _githubController.clear();
      });
    } catch (e, stack) {
      debugPrint('No se pudo seleccionar ZIP: $e\n$stack');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(ApiService.errorMessage(e))),
      );
    }
  }
  Future<void> _createProject() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    if (_selectedFileName == null && _githubController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sube un archivo o ingresa una URL de GitHub'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final githubUrl = _githubController.text.trim();
      if (githubUrl.isNotEmpty) {
        final uri = Uri.tryParse(githubUrl);
        if (uri == null || uri.scheme != 'https' || uri.host != 'github.com' ||
            uri.pathSegments.where((s) => s.isNotEmpty).length != 2) {
          throw const FormatException('Ingresa una URL como https://github.com/usuario/repositorio');
        }
      }
      final formData = FormData();
      if (githubUrl.isEmpty && _selectedFile != null) {
        formData.files.add(MapEntry('file', MultipartFile.fromBytes(
          _selectedFile!.bytes!, filename: _selectedFile!.name,
        )));
      }

      formData.fields.addAll([
        MapEntry('name', _nameController.text.trim()),
        MapEntry('description', _descriptionController.text.trim()),
        MapEntry('github_url', _githubController.text.trim()),
      ]);

      final response = await _api.createAndAnalyzeProject(formData);

      if (response.statusCode == 200 || response.statusCode == 201 || response.statusCode == 202) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proyecto creado; análisis iniciado'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        final error = response.data['error'] ?? 'Error al crear proyecto';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $error'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${ApiService.errorMessage(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 380,
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 600),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Nuevo Proyecto',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(
                        Icons.close,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      padding: EdgeInsets.zero,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Sube tu proyecto o clona desde GitHub',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nombre del proyecto',
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                  validator: (v) => v?.trim().isEmpty == true ? 'Nombre requerido' : null,
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: _descriptionController,
                  decoration: InputDecoration(
                    labelText: 'Descripción (opcional)',
                    labelStyle: const TextStyle(fontSize: 12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 10),

                GestureDetector(
                  onTap: _pickFile,
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: theme.colorScheme.outlineVariant.withOpacity(0.4),
                      ),
                      color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.1),
                    ),
                    child: Column(
                      children: [
                        Icon(
                          Icons.cloud_upload,
                          size: 32,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Haz clic para seleccionar archivo',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontSize: 12,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          'ZIP, TAR.GZ, .py, .js — máx. 50 MB',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 10,
                          ),
                        ),
                        if (_selectedFileName != null) ...[
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              color: theme.colorScheme.primary.withOpacity(0.1),
                              border: Border.all(
                                color: theme.colorScheme.primary.withOpacity(0.2),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.attach_file,
                                  size: 14,
                                  color: theme.colorScheme.primary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedFileName!,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    fontSize: 11,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),

                Row(
                  children: [
                    Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.3))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        'o',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    Expanded(child: Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.3))),
                  ],
                ),
                const SizedBox(height: 10),

                TextFormField(
                  controller: _githubController,
                  decoration: InputDecoration(
                    labelText: 'URL de GitHub',
                    hintText: 'https://github.com/usuario/repositorio',
                    labelStyle: const TextStyle(fontSize: 12),
                    prefixIcon: Icon(
                      Icons.code,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                  ),
                  style: TextStyle(color: theme.colorScheme.onSurface),
                ),
                const SizedBox(height: 16),

                GradientButton(
                  onPressed: _createProject,
                  isLoading: _isLoading,
                  text: 'Crear y analizar',
                  width: double.infinity,
                  height: 40,
                  fontSize: 13,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// EDIT PROJECT DIALOG
// ============================================================

class _EditProjectDialog extends StatefulWidget {
  final Project project;

  const _EditProjectDialog({required this.project});

  @override
  State<_EditProjectDialog> createState() => _EditProjectDialogState();
}

class _EditProjectDialogState extends State<_EditProjectDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final ApiService _api = ApiService();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = widget.project.name;
    _descriptionController.text = widget.project.description ?? '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _saveChanges() async {
    if (_isLoading || !_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await _api.put(
        '/api/projects/${widget.project.id}',
        data: {
          'name': _nameController.text.trim(),
          'description': _descriptionController.text.trim(),
        },
      );

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proyecto actualizado'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al actualizar'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${ApiService.errorMessage(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      backgroundColor: theme.colorScheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        padding: const EdgeInsets.all(20),
        width: 380,
        constraints: const BoxConstraints(maxWidth: 380),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Editar Proyecto',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      size: 20,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nombre del proyecto',
                  labelStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                ),
                style: TextStyle(color: theme.colorScheme.onSurface),
                validator: (v) => v?.trim().isEmpty == true ? 'Nombre requerido' : null,
              ),
              const SizedBox(height: 10),

              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Descripción',
                  labelStyle: const TextStyle(fontSize: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                ),
                style: TextStyle(color: theme.colorScheme.onSurface),
                maxLines: 3,
              ),
              const SizedBox(height: 16),

              Row(
                children: [
                  Expanded(
                    child: GradientButton(
                      onPressed: () => Navigator.pop(context),
                      text: 'Cancelar',
                      isOutlined: true,
                      height: 38,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: GradientButton(
                      onPressed: _saveChanges,
                      isLoading: _isLoading,
                      text: 'Guardar',
                      height: 38,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}