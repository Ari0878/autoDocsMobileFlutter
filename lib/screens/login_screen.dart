import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../services/auth_service.dart';
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

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _error = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.login(
      _emailController.text.trim(),
      _passwordController.text,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      setState(() {
        _isLoading = false;
        _error = authProvider.error ?? 'Error al iniciar sesión';
      });
    }
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
                        enabled: !_isLoading,
                      ),
                      const SizedBox(height: 16),
                      
                      PasswordField(
                        controller: _passwordController,
                        label: 'Contraseña',
                        enabled: !_isLoading,
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
                          onPressed: _isLoading ? null : () {
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
                            onPressed: _isLoading ? null : () {
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