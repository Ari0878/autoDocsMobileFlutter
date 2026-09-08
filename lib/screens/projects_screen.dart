import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'dart:async';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../models/project.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/project_card.dart';

class ProjectsScreen extends StatefulWidget {
  const ProjectsScreen({super.key});

  @override
  State<ProjectsScreen> createState() => _ProjectsScreenState();
}

class _ProjectsScreenState extends State<ProjectsScreen> {
  List<Project> _allProjects = [];
  List<Project> _filteredProjects = [];
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _error;
  Timer? _refreshTimer;
  final ApiService _api = ApiService();

  // Filtros
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatus = '';

  @override
  void initState() {
    super.initState();
    _loadProjects();
    _searchController.addListener(_filterProjects);
    _refreshTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) _loadProjects(showLoading: false);
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _refreshTimer?.cancel();
    super.dispose();
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
        _allProjects = data.map((p) => Project.fromJson(p)).toList();
        _filterProjects();

        setState(() {
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

  void _filterProjects() {
    final query = _searchController.text.toLowerCase();
    final status = _selectedStatus;

    setState(() {
      _filteredProjects = _allProjects.where((p) {
        final matchesSearch = p.name.toLowerCase().contains(query);
        final matchesStatus = status.isEmpty || p.status == status;
        return matchesSearch && matchesStatus;
      }).toList();
    });
  }

  Future<void> _deleteProject(Project project) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar proyecto'),
        content: Text('¿Eliminar "${project.name}"? Esta acción no se puede deshacer.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final response = await _api.delete('/api/projects/${project.id}');

      if (response.statusCode == 200 || response.statusCode == 204) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proyecto eliminado'),
              backgroundColor: Colors.green,
            ),
          );
          _loadProjects(showLoading: true);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error al eliminar proyecto'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // COLABORADORES - CORREGIDO DEFINITIVAMENTE
  // ============================================================

  Future<void> _showContributorsDialog(Project project) async {
    final theme = Theme.of(context);
    List<Map<String, dynamic>> contributors = [];
    bool loading = true;
    String? error;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) {
          // Cargar colaboradores al abrir el diálogo
          if (loading) {
            _loadContributors(project.id).then((data) {
              if (data != null) {
                try {
                  final rawContributors = data['contributors'] ?? [];
                  // Convertir correctamente a List<Map<String, dynamic>>
                  contributors = rawContributors.map<Map<String, dynamic>>((c) {
                    // Asegurar que cada campo tenga el tipo correcto
                    final name = c['name']?.toString() ?? c['username']?.toString() ?? 'Desconocido';
                    final email = c['email']?.toString() ?? '';
                    final commits = _safeParseInt(c['commits']);
                    final role = c['role']?.toString() ?? 'contributor';
                    final avatarUrl = c['avatar_url']?.toString();
                    
                    return {
                      'name': name,
                      'email': email,
                      'commits': commits,
                      'role': role,
                      'avatar_url': avatarUrl,
                    };
                  }).toList();
                  
                  setStateDialog(() {
                    loading = false;
                  });
                } catch (e) {
                  print('Error procesando colaboradores: $e');
                  setStateDialog(() {
                    error = 'Error al procesar datos de colaboradores';
                    loading = false;
                  });
                }
              } else {
                setStateDialog(() {
                  error = 'Error al cargar colaboradores';
                  loading = false;
                });
              }
            });
          }

          return Dialog(
            backgroundColor: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              width: 380,
              constraints: const BoxConstraints(
                maxWidth: 380,
                maxHeight: 500,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Header
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
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
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Colaboradores',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                project.name,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                        padding: EdgeInsets.zero,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Body
                  Expanded(
                    child: loading
                        ? const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                CircularProgressIndicator(),
                                SizedBox(height: 12),
                                Text('Cargando colaboradores...'),
                              ],
                            ),
                          )
                        : error != null
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.error_outline,
                                      color: Colors.red.shade400,
                                      size: 40,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      error!,
                                      style: TextStyle(
                                        color: Colors.red.shade400,
                                      ),
                                    ),
                                  ],
                                ),
                              )
                            : contributors.isEmpty
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.group_off,
                                          size: 40,
                                          color: theme.colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          'No se encontraron colaboradores',
                                          style: TextStyle(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Los colaboradores se detectan automáticamente desde Git',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            color: theme.colorScheme.onSurfaceVariant,
                                          ),
                                          textAlign: TextAlign.center,
                                        ),
                                      ],
                                    ),
                                  )
                                : _buildContributorsList(context, contributors),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // Función segura para parsear números
  int _safeParseInt(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) {
      return int.tryParse(value) ?? 0;
    }
    return 0;
  }

  Future<Map<String, dynamic>?> _loadContributors(String projectId) async {
    try {
      final response = await _api.get('/api/projects/$projectId/contributors');
      if (response.statusCode == 200) {
        return response.data;
      }
      return null;
    } catch (e) {
      print('Error loading contributors: $e');
      return null;
    }
  }

  Widget _buildContributorsList(BuildContext context, List<Map<String, dynamic>> contributors) {
    final theme = Theme.of(context);
    final colors = [
      Colors.blue.shade400,
      Colors.indigo.shade400,
      Colors.green.shade400,
      Colors.orange.shade400,
      Colors.red.shade400,
      Colors.pink.shade400,
      Colors.purple.shade400,
      Colors.teal.shade400,
      Colors.amber.shade400,
      Colors.deepPurple.shade400,
    ];

    // Ordenar por commits (descendente) - usando safe get
    contributors.sort((a, b) {
      final commitsA = (a['commits'] as int?) ?? 0;
      final commitsB = (b['commits'] as int?) ?? 0;
      return commitsB.compareTo(commitsA);
    });

    final totalCommits = contributors.fold<int>(
      0,
      (sum, c) => sum + ((c['commits'] as int?) ?? 0),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              '${contributors.length} colaboradores',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '· $totalCommits commits totales',
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: contributors.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (ctx, index) {
              final contrib = contributors[index];
              final name = contrib['name']?.toString() ?? 'Desconocido';
              final email = contrib['email']?.toString() ?? '';
              final commits = (contrib['commits'] as int?) ?? 0;
              final role = contrib['role']?.toString() ?? '';
              final maxCommits = contributors.isNotEmpty
                  ? (contributors.first['commits'] as int? ?? 1)
                  : 1;
              final barWidth = maxCommits > 0 ? (commits / maxCommits).clamp(0.0, 1.0) : 0.0;

              final initials = name
                  .split(' ')
                  .where((s) => s.isNotEmpty)
                  .map((s) => s[0])
                  .take(2)
                  .join()
                  .toUpperCase();

              final color = colors[index % colors.length];

              return Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
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
                      width: 32,
                      height: 32,
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
                            fontSize: 11,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
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
                              style: theme.textTheme.bodySmall?.copyWith(
                                fontSize: 10,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: barWidth,
                                    backgroundColor: theme.colorScheme.outlineVariant.withOpacity(0.2),
                                    color: Colors.blue.shade400,
                                    minHeight: 4,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '$commits commits',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  fontSize: 10,
                                  fontFamily: 'JetBrains Mono',
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
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRoleChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withOpacity(0.15),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final user = context.watch<AuthProvider>().user;
    final plan = user?.plan ?? 'free';

    final limits = {'free': 3, 'pro': 20, 'enterprise': -1};
    final limit = limits[plan] ?? 3;
    final canCreate = limit == -1 || _allProjects.length < limit;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: RefreshIndicator(
        onRefresh: () => _loadProjects(showLoading: true),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              _buildHeader(context, canCreate),
              const SizedBox(height: 16),

              // Filtros
              _buildFilters(context),
              const SizedBox(height: 16),

              // Proyectos
              _buildProjectsList(context),
              const SizedBox(height: 80),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, bool canCreate) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Proyectos',
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 24,
              ),
            ),
            Text(
              '${_allProjects.length} proyecto${_allProjects.length != 1 ? 's' : ''}',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontSize: 12,
                letterSpacing: 0.3,
              ),
            ),
          ],
        ),
        Row(
          children: [
            // Theme toggle button
            IconButton(
              onPressed: _toggleTheme,
              icon: Icon(
                isDark ? Icons.light_mode : Icons.dark_mode,
              ),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            const SizedBox(width: 6),
            // New project button
            GradientButton(
              onPressed: canCreate
                  ? () => _showCreateProjectDialog(context)
                  : () => _showLimitDialog(context),
              text: 'Nuevo',
              icon: Icons.upload,
              width: 80,
              height: 38,
              fontSize: 12,
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

  Widget _buildFilters(BuildContext context) {
    final theme = Theme.of(context);

    final statusOptions = [
      {'value': '', 'label': 'Todos los estados'},
      {'value': 'completed', 'label': 'Completados'},
      {'value': 'analyzing', 'label': 'Analizando'},
      {'value': 'pending', 'label': 'Pendientes'},
      {'value': 'error', 'label': 'Con error'},
    ];

    return Row(
      children: [
        // Search input
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.2),
              ),
            ),
            child: TextField(
              controller: _searchController,
              style: theme.textTheme.bodyMedium,
              decoration: InputDecoration(
                hintText: 'Buscar proyecto...',
                hintStyle: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                ),
                prefixIcon: Icon(
                  Icons.search,
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                  size: 20,
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Status filter
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: theme.colorScheme.outlineVariant.withOpacity(0.2),
            ),
          ),
          child: DropdownButton<String>(
            value: _selectedStatus.isEmpty ? null : _selectedStatus,
            hint: Text(
              'Estado',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            underline: const SizedBox(),
            items: statusOptions.map((option) {
              return DropdownMenuItem<String>(
                value: option['value'],
                child: Text(
                  option['label']!,
                  style: theme.textTheme.bodySmall,
                ),
              );
            }).toList(),
            onChanged: (value) {
              setState(() {
                _selectedStatus = value ?? '';
                _filterProjects();
              });
            },
            style: theme.textTheme.bodyMedium,
            dropdownColor: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ],
    );
  }

  Widget _buildProjectsList(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return GlassCard(
        padding: const EdgeInsets.all(32),
        child: const Center(
          child: Column(
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('Cargando proyectos...'),
            ],
          ),
        ),
      );
    }

    if (_error != null) {
      return GlassCard(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error, size: 40),
              const SizedBox(height: 8),
              Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => _loadProjects(showLoading: true),
                child: const Text('Reintentar'),
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredProjects.isEmpty) {
      return GlassCard(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Icon(
              Icons.folder_open,
              size: 40,
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
            ),
            const SizedBox(height: 10),
            Text(
              'Sin proyectos',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'No se encontraron proyectos con estos filtros.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      children: _filteredProjects.map((project) {
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: _buildProjectItem(context, project),
        );
      }).toList(),
    );
  }

  Widget _buildProjectItem(BuildContext context, Project project) {
    final theme = Theme.of(context);

    final statusLabels = {
      'completed': '✓ Completado',
      'analyzing': '⟳ Analizando',
      'pending': '○ Pendiente',
      'error': '✕ Error',
    };

    final statusColors = {
      'completed': Colors.green,
      'analyzing': Colors.orange,
      'pending': Colors.grey,
      'error': Colors.red,
    };

    final langIcons = {
      'Python': '🐍',
      'JavaScript': '⚡',
      'TypeScript': '🔷',
      'Java': '☕',
      'PHP': '🐘',
      'Go': '🔵',
      'Ruby': '💎',
      'C++': '⚙️',
      'C#': '🎯',
      'Rust': '🦀',
    };

    final statusColor = statusColors[project.status] ?? Colors.grey;
    final statusLabel = statusLabels[project.status] ?? project.status;
    final langIcon = langIcons[project.language] ?? '📁';

    final q = project.stats?.qualityScore ?? 0;
    final qColor = q >= 70 ? Colors.green : q >= 40 ? Colors.orange : Colors.red;

    return GestureDetector(
      onTap: () => Navigator.pushNamed(context, '/project', arguments: project.id),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Language icon
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                color: theme.colorScheme.primary.withOpacity(0.1),
                border: Border.all(
                  color: theme.colorScheme.primary.withOpacity(0.2),
                ),
              ),
              child: Center(
                child: Text(
                  langIcon,
                  style: const TextStyle(fontSize: 20),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Project info
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    project.name,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${project.language ?? 'Desconocido'} · ${_formatDate(project.createdAt)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            // Stats (desktop)
            if (MediaQuery.of(context).size.width > 600) ...[
              _buildStat('Archivos', '${project.stats?.files ?? 0}'),
              const SizedBox(width: 16),
              _buildStat('Funciones', '${project.stats?.functions ?? 0}'),
              const SizedBox(width: 16),
              _buildStat('Endpoints', '${project.stats?.endpoints ?? 0}'),
              if (project.isCompleted) ...[
                const SizedBox(width: 16),
                _buildStat('Calidad', '${q}%', color: qColor),
              ],
            ],
            // Contributors button
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              child: IconButton(
                onPressed: () => _showContributorsDialog(project),
                icon: const Icon(Icons.group, size: 18),
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.secondary.withOpacity(0.1),
                  foregroundColor: theme.colorScheme.secondary,
                  padding: const EdgeInsets.all(6),
                  minimumSize: const Size(32, 32),
                ),
                tooltip: 'Colaboradores',
              ),
            ),
            // Status badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: statusColor.withOpacity(0.1),
                border: Border.all(color: statusColor.withOpacity(0.2)),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                  fontSize: 8,
                  fontWeight: FontWeight.w700,
                  color: statusColor,
                ),
              ),
            ),
            // Delete button
            IconButton(
              onPressed: () => _deleteProject(project),
              icon: const Icon(Icons.delete, size: 18),
              style: IconButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant.withOpacity(0.4),
                padding: const EdgeInsets.all(6),
                minimumSize: const Size(32, 32),
              ),
              tooltip: 'Eliminar',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value, {Color? color}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 9,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];
    return '${date.day} ${months[date.month - 1]} ${date.year}';
  }

  void _showCreateProjectDialog(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const _CreateProjectDialog(),
    ).then((_) => _loadProjects(showLoading: true));
  }

  void _showLimitDialog(BuildContext context) {
    final theme = Theme.of(context);

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
              'Has alcanzado el límite de proyectos para tu plan actual.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Actualiza al plan Pro para crear más proyectos.',
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
  String? _selectedFileName;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _githubController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    setState(() {
      _selectedFileName = 'proyecto.zip';
    });
  }

  Future<void> _createProject() async {
    if (!_formKey.currentState!.validate()) return;

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
      final formData = FormData();

      formData.fields.addAll([
        MapEntry('name', _nameController.text.trim()),
        MapEntry('description', _descriptionController.text.trim()),
        MapEntry('github_url', _githubController.text.trim()),
      ]);

      final response = await _api.post(
        '/api/projects/',
        data: formData,
        isMultipart: true,
      );

      if (response.statusCode == 200 || response.statusCode == 201) {
        if (mounted) {
          Navigator.pop(context, true);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Proyecto creado exitosamente'),
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
            content: Text('Error: ${e.toString()}'),
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
        constraints: const BoxConstraints(maxWidth: 380, maxHeight: 550),
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
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close, size: 20),
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
                  ),
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
                  ),
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
                          style: theme.textTheme.bodyMedium?.copyWith(fontSize: 12),
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
                                const Icon(Icons.attach_file, size: 14),
                                const SizedBox(width: 4),
                                Text(
                                  _selectedFileName!,
                                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 11),
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
                    prefixIcon: const Icon(Icons.code, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
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