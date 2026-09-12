import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/theme_provider.dart';
import '../models/user.dart';
import '../services/api_service.dart';
import '../widgets/glass_card.dart';
import '../widgets/gradient_button.dart';
import '../widgets/password_field.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final ApiService _api = ApiService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _confirmPasswordController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  String? _error;
  String? _success;
  User? _user;
  Map<String, dynamic>? _planData;
  int _projectsUsed = 0;
  int _projectsLimit = 3;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    try {
      // 1. Cargar datos del usuario
      final userResponse = await _api.get('/api/auth/me');
      if (userResponse.statusCode == 200) {
        final userData = userResponse.data;
        _user = User.fromJson(userData);
        _nameController.text = _user?.name ?? '';
        _emailController.text = _user?.email ?? '';
      }

      // 2. Cargar plan del usuario
      final planResponse = await _api.get('/api/payments/my-plan');
      if (planResponse.statusCode == 200) {
        _planData = planResponse.data;
      }

      // 3. Cargar proyectos para contar los usados
      final projectsResponse = await _api.get('/api/projects/');
      if (projectsResponse.statusCode == 200) {
        final projects = projectsResponse.data as List;
        _projectsUsed = projects.length;

        final plan = _planData?['plan'] ?? 'free';
        final limits = {'free': 3, 'pro': 20, 'enterprise': -1};
        _projectsLimit = limits[plan] ?? 3;
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Error al cargar el perfil';
      });
    }
  }

  Future<void> _saveProfile() async {
    if (_isSaving) return;

    final name = _nameController.text.trim();
    final password = _passwordController.text;
    final confirmPassword = _confirmPasswordController.text;

    // Validaciones
    if (name.isEmpty) {
      setState(() {
        _error = 'El nombre no puede estar vacío';
        _success = null;
      });
      return;
    }

    if (password.isNotEmpty && password != confirmPassword) {
      setState(() {
        _error = 'Las contraseñas no coinciden';
        _success = null;
      });
      return;
    }

    if (password.isNotEmpty && password.length < 6) {
      setState(() {
        _error = 'La contraseña debe tener al menos 6 caracteres';
        _success = null;
      });
      return;
    }

    setState(() {
      _isSaving = true;
      _error = null;
      _success = null;
    });

    try {
      final body = <String, dynamic>{'name': name};
      if (password.isNotEmpty) {
        body['password'] = password;
      }

      final response = await _api.put(
        '/api/auth/me',
        data: body,
      );

      if (response.statusCode == 200) {
        final updatedUser = response.data;
        if (updatedUser['name'] != null) {
          _nameController.text = updatedUser['name'];
        }

        // Actualizar usuario en el provider
        final authProvider = context.read<AuthProvider>();
        if (authProvider.user != null) {
          final newUser = User.fromJson(updatedUser);
          authProvider.updateUser(newUser);
        }

        setState(() {
          _success = 'Perfil actualizado correctamente';
          _passwordController.clear();
          _confirmPasswordController.clear();
          _isSaving = false;
        });

        // Ocultar mensaje de éxito después de 3 segundos
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            setState(() {
              _success = null;
            });
          }
        });
      } else {
        setState(() {
          _error = response.data['error'] ?? 'Error al actualizar el perfil';
          _isSaving = false;
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error de conexión';
        _isSaving = false;
      });
    }
  }

  String _getPlanName(String? plan) {
    switch (plan) {
      case 'pro': return 'Plan Pro';
      case 'enterprise': return 'Plan Enterprise';
      default: return 'Plan Gratuito';
    }
  }

  String _getPlanDetails(String? plan) {
    switch (plan) {
      case 'pro': return '20 proyectos, 100 análisis/mes, PDF + IA';
      case 'enterprise': return 'Proyectos ilimitados, análisis ilimitados';
      default: return '3 proyectos, 10 análisis/mes';
    }
  }

  String _getPlanPrice(String? plan) {
    switch (plan) {
      case 'pro': return '\$350';
      case 'enterprise': return '\$850';
      default: return '\$0';
    }
  }

  double _getProgressValue() {
    if (_projectsLimit == -1) return 0;
    return (_projectsUsed / _projectsLimit).clamp(0.0, 1.0);
  }

  Color _getProgressColor() {
    if (_projectsLimit == -1) return Colors.blue;
    final progress = _getProgressValue();
    if (progress >= 1.0) return Colors.red;
    if (progress >= 0.8) return Colors.orange;
    return Colors.blue;
  }

  String _getProjectsText() {
    if (_projectsLimit == -1) {
      return '$_projectsUsed / ∞';
    }
    return '$_projectsUsed / $_projectsLimit';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Header
                    _buildHeader(context),
                    const SizedBox(height: 20),

                    // Grid: Avatar + Formulario
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth > 800) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                flex: 1,
                                child: _buildAvatarCard(context),
                              ),
                              const SizedBox(width: 20),
                              Expanded(
                                flex: 2,
                                child: _buildProfileForm(context),
                              ),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            _buildAvatarCard(context),
                            const SizedBox(height: 16),
                            _buildProfileForm(context),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================

  Widget _buildHeader(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Título - parte izquierda
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.account_circle,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Panel de usuario',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Mi Perfil',
                style: theme.textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 24,
                  foreground: Paint()
                    ..shader = LinearGradient(
                      colors: isDark
                          ? [Colors.white, theme.colorScheme.primary]
                          : [theme.colorScheme.onSurface, theme.colorScheme.primary],
                    ).createShader(const Rect.fromLTWH(0, 0, 200, 40)),
                ),
              ),
              Text(
                'Administra tu identidad y credenciales',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Solo el toggle de tema queda en el header; "Cerrar sesión" se
        // movió a la tarjeta de la cuenta, donde es una acción de cuenta
        // y no compite visualmente con el título.
        IconButton(
          onPressed: _toggleTheme,
          icon: Icon(
            isDark ? Icons.light_mode : Icons.dark_mode,
            size: 20,
          ),
          style: IconButton.styleFrom(
            backgroundColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.3),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.all(8),
            minimumSize: const Size(36, 36),
          ),
        ),
      ],
    );
  }

  void _toggleTheme() {
    final themeProvider = context.read<ThemeProvider>();
    themeProvider.toggleTheme();
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cerrar sesión'),
        content: const Text('¿Estás seguro de que deseas cerrar sesión?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              _logout();
            },
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: const Text('Cerrar sesión'),
          ),
        ],
      ),
    );
  }

  void _logout() {
    final authProvider = context.read<AuthProvider>();
    authProvider.logout();
    Navigator.pushReplacementNamed(context, '/login');
  }

  // ============================================================
  // AVATAR CARD
  // ============================================================

  Widget _buildAvatarCard(BuildContext context) {
    final theme = Theme.of(context);
    final name = _user?.name ?? 'Usuario';
    final email = _user?.email ?? '';
    final initials = name
        .split(' ')
        .where((s) => s.isNotEmpty)
        .map((s) => s[0])
        .take(2)
        .join()
        .toUpperCase();

    return GlassCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          // Avatar
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              ),
              boxShadow: [
                BoxShadow(
                  color: theme.colorScheme.primary.withOpacity(0.3),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Center(
              child: Text(
                initials.isEmpty ? '👤' : initials,
                style: const TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              email,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.center,
            children: [
              _buildBadge(
                context,
                'Verificado',
                Icons.verified,
                theme.colorScheme.primary,
              ),
              _buildBadge(
                context,
                'Usuario activo',
                Icons.badge,
                theme.colorScheme.primary,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
          const SizedBox(height: 12),
          _buildInfoRow(
            context,
            'Último acceso',
            '—',
            Icons.schedule,
          ),
          const SizedBox(height: 8),
          _buildInfoRow(
            context,
            '2FA',
            'Activado',
            Icons.security,
            valueColor: Colors.green,
          ),
          const SizedBox(height: 16),
          Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
          const SizedBox(height: 4),
          // Acción de cierre de sesión: vive al final de la tarjeta de
          // cuenta como un enlace discreto, no como un botón prominente
          // compitiendo con el resto de la interfaz.
          Center(
            child: TextButton.icon(
              onPressed: () => _showLogoutDialog(context),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                minimumSize: const Size(0, 0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              icon: const Icon(Icons.logout, size: 15),
              label: const Text(
                'Cerrar sesión',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBadge(BuildContext context, String label, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    String label,
    String value,
    IconData icon, {
    Color? valueColor,
  }) {
    final theme = Theme.of(context);

    return Row(
      children: [
        Icon(icon, size: 16, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
            ),
          ),
        ),
        Text(
          value,
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w500,
            color: valueColor ?? theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  // ============================================================
  // PROFILE FORM
  // ============================================================

  Widget _buildProfileForm(BuildContext context) {
    final theme = Theme.of(context);
    final plan = _planData?['plan'] ?? 'free';

    return GlassCard(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Form header
          Row(
            children: [
              Icon(
                Icons.edit_note,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Información personal',
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
          const SizedBox(height: 20),

          // Name & Email
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Nombre completo',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.person, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
                      ),
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
                      'Correo electrónico',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurfaceVariant,
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _emailController,
                      readOnly: true,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.email, size: 18),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        filled: true,
                        fillColor: theme.colorScheme.onSurface.withOpacity(0.05),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Plan actual
          Text(
            'Plan actual',
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: theme.colorScheme.outlineVariant.withOpacity(0.2),
              ),
              color: theme.colorScheme.surfaceContainerHighest.withOpacity(0.2),
            ),
            child: Column(
              children: [
                // FIX OVERFLOW (11px): antes la Column con el nombre y los
                // detalles del plan no tenía Expanded. Con nombres/detalles
                // largos (p. ej. "Plan Enterprise" + su descripción) y poco
                // ancho disponible (pantallas angostas), el Row con
                // spaceBetween no tenía forma de ceder espacio y se
                // desbordaba. Envolver esa Column en Expanded permite que
                // el texto se ajuste (wrap) al ancho disponible en vez de
                // empujar el layout más allá del límite.
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getPlanName(plan),
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            _getPlanDetails(plan),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _getPlanPrice(plan),
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Text(
                          '/mes',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Divider(color: theme.colorScheme.outlineVariant.withOpacity(0.2)),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Proyectos usados',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      ),
                    ),
                    Text(
                      _getProjectsText(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: _getProgressValue(),
                    backgroundColor: theme.colorScheme.outlineVariant.withOpacity(0.2),
                    color: _getProgressColor(),
                    minHeight: 6,
                  ),
                ),
                const SizedBox(height: 12),
                GradientButton(
                  onPressed: () => Navigator.pushNamed(context, '/pricing'),
                  text: 'Cambiar plan',
                  icon: Icons.upgrade,
                  isOutlined: true,
                  width: double.infinity,
                  height: 38,
                  fontSize: 12,
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Password fields
          Row(
            children: [
              Expanded(
                child: PasswordField(
                  controller: _passwordController,
                  label: 'Nueva contraseña',
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: PasswordField(
                  controller: _confirmPasswordController,
                  label: 'Confirmar contraseña',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Mínimo 6 caracteres, déjala vacía si no deseas cambiarla',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 16),

          // Security tip
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.primary.withOpacity(0.06),
              border: Border.all(
                color: theme.colorScheme.primary.withOpacity(0.2),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Recomendación de seguridad: Utiliza una contraseña única, combina mayúsculas, números y símbolos. Evita palabras comunes.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontSize: 11,
                      color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                      height: 1.5,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Error / Success messages
          if (_error != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.error.withOpacity(0.1),
                border: Border.all(
                  color: theme.colorScheme.error.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.error,
                    color: theme.colorScheme.error,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_success != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.green.withOpacity(0.1),
                border: Border.all(
                  color: Colors.green.withOpacity(0.2),
                ),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _success!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 16),

          // Action buttons
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              GradientButton(
                onPressed: _loadProfile,
                text: 'Recargar datos',
                icon: Icons.refresh,
                isOutlined: true,
                height: 40,
                fontSize: 12,
              ),
              const SizedBox(width: 10),
              GradientButton(
                onPressed: _saveProfile,
                isLoading: _isSaving,
                text: 'Guardar cambios',
                icon: Icons.save,
                height: 40,
                fontSize: 12,
              ),
            ],
          ),
        ],
      ),
    );
  }
}