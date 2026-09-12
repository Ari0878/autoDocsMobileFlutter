import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
import '../services/biometric_auth_service.dart';
import '../widgets/gradient_button.dart';
import '../widgets/password_field.dart';
import '../utils/validators.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;

  // ============================================================
  // BIOMETRÍA (candado local, no autentica contra el backend)
  // ============================================================
  final BiometricAuthService _biometricAuth = BiometricAuthService();
  bool _checkingBiometric = true;
  bool _biometricAvailable = false; // el dispositivo tiene huella/Face ID
  bool _biometricEnabled = false;   // el usuario ya guardó credenciales
  bool _isBiometricLoading = false;

  @override
  void initState() {
    super.initState();
    _initBiometricState();
  }

  Future<void> _initBiometricState() async {
    final available = await _biometricAuth.isBiometricAvailable();
    final enabled = await _biometricAuth.isBiometricLoginEnabled();

    // 🔍 LOG TEMPORAL: confirma qué está detectando el servicio al arrancar.
    debugPrint('🔐 [initBiometricState] available=$available enabled=$enabled');

    if (!mounted) return;
    setState(() {
      _biometricAvailable = available;
      _biometricEnabled = enabled;
      _checkingBiometric = false;
    });
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  // ============================================================
  // LOGIN CON FORMULARIO (usuario y contraseña)
  // ============================================================

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    final email = _emailController.text.trim();
    final password = _passwordController.text;

    final success = await _performLogin(email, password);
    if (!success) return;

    // Si el dispositivo soporta huella y el usuario aún no la activó,
    // le ofrecemos guardar estas credenciales cifradas para la próxima vez.
    if (_biometricAvailable && !_biometricEnabled) {
      await _offerEnableBiometric(email, password);
    }

    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  // ============================================================
  // LOGIN CON HUELLA (reutiliza credenciales guardadas localmente)
  // ============================================================

  Future<void> _handleBiometricLogin() async {
    if (_isLoading || _isBiometricLoading) return;

    setState(() {
      _isBiometricLoading = true;
      _error = null;
    });

    final authenticated = await _biometricAuth.authenticate(
      reason: 'Confirma tu huella para iniciar sesión',
    );

    debugPrint('🔐 [handleBiometricLogin] authenticated=$authenticated');

    if (!mounted) return;

    if (!authenticated) {
      setState(() {
        _isBiometricLoading = false;
        _error = 'No se pudo verificar tu huella. Intenta de nuevo.';
      });
      return;
    }

    final stored = await _biometricAuth.getStoredCredentials();
    debugPrint('🔐 [handleBiometricLogin] stored=${stored != null}');

    if (!mounted) return;

    if (stored == null) {
      setState(() {
        _isBiometricLoading = false;
        _biometricEnabled = false;
        _error = 'No hay una sesión guardada. Inicia sesión con tu contraseña.';
      });
      return;
    }

    final success = await _performLogin(stored.email, stored.password);
    setState(() => _isBiometricLoading = false);

    if (!success) return;
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/home');
  }

  /// Lógica común de autenticación contra el backend. No navega ni
  /// gestiona la huella; solo hace login y actualiza el estado de error.
  Future<bool> _performLogin(String email, String password) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(email, password);

    if (!mounted) return false;

    if (!success) {
      setState(() {
        _isLoading = false;
        _error = authProvider.error ?? 'Error al iniciar sesión';
      });
      // Si las credenciales guardadas ya no son válidas, las borramos para
      // no quedar en un ciclo de "huella válida, login inválido".
      if (_biometricEnabled) {
        _biometricAuth.disableBiometricLogin();
        setState(() => _biometricEnabled = false);
      }
      return false;
    }

    setState(() => _isLoading = false);
    return true;
  }

  Future<void> _offerEnableBiometric(String email, String password) async {
    final theme = Theme.of(context);
    final accept = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.fingerprint, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            // 🔧 FIX overflow: el texto necesita Expanded para hacer wrap
            // en vez de desbordar el ancho del diálogo.
            Expanded(
              child: Text(
                'Inicio rápido con huella',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        content: const Text(
          '¿Quieres usar tu huella para entrar más rápido la próxima vez? '
          'Tus credenciales se guardan cifradas solo en este dispositivo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Ahora no'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Activar'),
          ),
        ],
      ),
    );

    debugPrint('🔐 [offerEnableBiometric] accept=$accept');
    if (accept != true) return;

    // Confirmamos con una huella real antes de guardar nada, para asegurar
    // que quien activa la función es realmente el dueño del dedo.
    final confirmed = await _biometricAuth.authenticate(
      reason: 'Confirma tu huella para activar el inicio rápido',
    );

    // 🔍 LOG TEMPORAL: si esto imprime "false" o no imprime nada, el problema
    // está dentro de BiometricAuthService.authenticate() (revisa permisos
    // nativos de local_auth en Info.plist / AndroidManifest.xml).
    debugPrint('🔐 [offerEnableBiometric] confirmed=$confirmed');
    if (!confirmed) return;

    try {
      await _biometricAuth.enableBiometricLogin(email, password);
      debugPrint('🔐 [offerEnableBiometric] credenciales guardadas OK');
    } catch (e, st) {
      // 🔍 LOG TEMPORAL: si esto se imprime, el problema está en cómo
      // BiometricAuthService.enableBiometricLogin() guarda las credenciales
      // (por ejemplo un error de flutter_secure_storage).
      debugPrint('🔐 [offerEnableBiometric] ERROR guardando credenciales: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() {
        _error = 'No se pudo activar el inicio con huella. Intenta de nuevo.';
      });
      return;
    }

    if (!mounted) return;
    setState(() => _biometricEnabled = true);
  }

  void _forgetBiometricLogin() async {
    await _biometricAuth.disableBiometricLogin();
    if (!mounted) return;
    setState(() => _biometricEnabled = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Se olvidó la huella guardada en este dispositivo')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                // Back button
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back),
                  padding: EdgeInsets.zero,
                  alignment: Alignment.centerLeft,
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  'Bienvenido de vuelta',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Inicia sesión para continuar',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 32),

                // Form
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _emailController,
                        decoration: InputDecoration(
                          labelText: 'Correo electrónico',
                          prefixIcon: const Icon(Icons.email_outlined),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          filled: true,
                          fillColor: Colors.black.withOpacity(0.3),
                        ),
                        style: const TextStyle(color: Colors.white),
                        keyboardType: TextInputType.emailAddress,
                        validator: Validators.validateEmail,
                        enabled: !_isLoading && !_isBiometricLoading,
                      ),
                      const SizedBox(height: 16),

                      PasswordField(
                        controller: _passwordController,
                        label: 'Contraseña',
                        enabled: !_isLoading && !_isBiometricLoading,
                        validator: Validators.validatePassword,
                      ),

                      if (_error != null) ...[
                        const SizedBox(height: 16),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.error.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: theme.colorScheme.error.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.error_outline,
                                color: theme.colorScheme.error,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _error!,
                                  style: TextStyle(
                                    color: theme.colorScheme.error,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // Forgot password
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: (_isLoading || _isBiometricLoading) ? null : () {
                            _showForgotPasswordDialog(context);
                          },
                          child: Text(
                            '¿Olvidaste tu contraseña?',
                            style: TextStyle(
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Login button
                      GradientButton(
                        onPressed: _handleLogin,
                        isLoading: _isLoading,
                        text: 'Iniciar sesión',
                        width: double.infinity,
                      ),

                      // ============================================================
                      // BLOQUE DE HUELLA
                      // ============================================================
                      if (!_checkingBiometric && _biometricAvailable && _biometricEnabled) ...[
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            Expanded(
                              child: Divider(
                                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.2),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              child: Text(
                                'o',
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Divider(
                                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.2),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Center(
                          child: InkWell(
                            onTap: (_isLoading || _isBiometricLoading)
                                ? null
                                : _handleBiometricLogin,
                            borderRadius: BorderRadius.circular(100),
                            child: Container(
                              width: 64,
                              height: 64,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.primary.withOpacity(0.1),
                                border: Border.all(
                                  color: theme.colorScheme.primary.withOpacity(0.3),
                                ),
                              ),
                              child: _isBiometricLoading
                                  ? Padding(
                                      padding: const EdgeInsets.all(18),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: theme.colorScheme.primary,
                                      ),
                                    )
                                  : Icon(
                                      Icons.fingerprint,
                                      size: 36,
                                      color: theme.colorScheme.primary,
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            'Iniciar sesión con huella',
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurfaceVariant.withOpacity(0.7),
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Center(
                          child: TextButton(
                            onPressed: (_isLoading || _isBiometricLoading)
                                ? null
                                : _forgetBiometricLogin,
                            child: Text(
                              'Olvidar huella guardada',
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onSurfaceVariant.withOpacity(0.5),
                              ),
                            ),
                          ),
                        ),
                      ],

                      const SizedBox(height: 20),

                      // Register link
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '¿No tienes cuenta?',
                            style: TextStyle(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          TextButton(
                            onPressed: (_isLoading || _isBiometricLoading) ? null : () {
                              Navigator.pushReplacementNamed(context, '/register');
                            },
                            child: Text(
                              'Regístrate',
                              style: TextStyle(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPasswordDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => _ForgotPasswordDialog(),
    );
  }
}

class _ForgotPasswordDialog extends StatefulWidget {
  @override
  State<_ForgotPasswordDialog> createState() => _ForgotPasswordDialogState();
}

class _ForgotPasswordDialogState extends State<_ForgotPasswordDialog> {
  final _emailController = TextEditingController();
  final _codeController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _error;
  String? _success;
  int _step = 1; // 1: email, 2: code, 3: new password
  String? _email;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _sendCode() async {
    if (_emailController.text.trim().isEmpty) {
      setState(() => _error = 'Ingresa tu correo electrónico');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    final authService = AuthService();
    final response = await authService.forgotPassword(_emailController.text.trim());

    if (!mounted) return;

    if (response.success) {
      setState(() {
        _email = _emailController.text.trim();
        _step = 2;
        _isLoading = false;
        _success = 'Código enviado a tu correo';
      });
    } else {
      setState(() {
        _error = response.error ?? 'Error al enviar código';
        _isLoading = false;
      });
    }
  }

  Future<void> _verifyCode() async {
    if (_codeController.text.trim().length != 6) {
      setState(() => _error = 'Ingresa el código de 6 dígitos');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    final authService = AuthService();
    final response = await authService.verifyCode(
      _email!,
      _codeController.text.trim(),
    );

    if (!mounted) return;

    if (response.success) {
      setState(() {
        _step = 3;
        _isLoading = false;
        _success = 'Código verificado';
      });
    } else {
      setState(() {
        _error = response.error ?? 'Código inválido';
        _isLoading = false;
      });
    }
  }

  Future<void> _resetPassword() async {
    if (_passwordController.text.length < 8) {
      setState(() => _error = 'La contraseña debe tener mínimo 8 caracteres');
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _success = null;
    });

    final authService = AuthService();
    final response = await authService.resetPassword(
      _email!,
      _codeController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (response.success) {
      setState(() {
        _success = '¡Contraseña cambiada exitosamente!';
        _isLoading = false;
      });
      Future.delayed(const Duration(seconds: 2), () {
        Navigator.pop(context);
      });
    } else {
      setState(() {
        _error = response.error ?? 'Error al cambiar contraseña';
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
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _step == 1 ? 'Recuperar contraseña' :
                    _step == 2 ? 'Verificar código' :
                    'Nueva contraseña',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.error.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.error_outline,
                      color: theme.colorScheme.error,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: theme.colorScheme.error,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_success != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.green.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.green, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _success!,
                        style: const TextStyle(
                          color: Colors.green,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            if (_step == 1) ...[
              TextFormField(
                controller: _emailController,
                decoration: InputDecoration(
                  labelText: 'Correo electrónico',
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.3),
                ),
                style: const TextStyle(color: Colors.white),
                keyboardType: TextInputType.emailAddress,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 20),
              GradientButton(
                onPressed: _sendCode,
                isLoading: _isLoading,
                text: 'Enviar código',
                width: double.infinity,
              ),
            ],

            if (_step == 2) ...[
              TextFormField(
                controller: _codeController,
                decoration: InputDecoration(
                  labelText: 'Código de 6 dígitos',
                  prefixIcon: const Icon(Icons.pin),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  filled: true,
                  fillColor: Colors.black.withOpacity(0.3),
                ),
                style: const TextStyle(color: Colors.white, fontSize: 20),
                keyboardType: TextInputType.number,
                maxLength: 6,
                textAlign: TextAlign.center,
                enabled: !_isLoading,
              ),
              const SizedBox(height: 8),
              GradientButton(
                onPressed: _verifyCode,
                isLoading: _isLoading,
                text: 'Verificar código',
                width: double.infinity,
              ),
            ],

            if (_step == 3) ...[
              PasswordField(
                controller: _passwordController,
                label: 'Nueva contraseña',
                enabled: !_isLoading,
              ),
              const SizedBox(height: 8),
              Text(
                'Mínimo 8 caracteres, 1 mayúscula, 1 minúscula y 1 número',
                style: TextStyle(
                  color: theme.colorScheme.onSurfaceVariant.withOpacity(0.6),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 20),
              GradientButton(
                onPressed: _resetPassword,
                isLoading: _isLoading,
                text: 'Cambiar contraseña',
                width: double.infinity,
              ),
            ],
          ],
        ),
      ),
    );
  }
}