import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../widgets/gradient_button.dart';
import '../widgets/password_field.dart';
import '../utils/constants.dart';
import '../utils/validators.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  
  String _selectedPlan = 'free';
  bool _isLoading = false;
  String? _error;
  int _currentStep = 1;
  bool _acceptedTerms = false;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleRegister() async {
    if (_currentStep == 1) {
      if (!_formKey.currentState!.validate()) return;
      if (!_acceptedTerms) {
        setState(() => _error = 'Acepta los Términos y Condiciones');
        return;
      }
      setState(() {
        _currentStep = 2;
        _error = null;
      });
      return;
    }

    if (_currentStep == 2) {
      if (_selectedPlan == 'free') {
        await _doRegister();
      } else {
        setState(() {
          _currentStep = 3;
          _error = null;
        });
      }
      return;
    }

    if (_currentStep == 3) {
      await _doRegister();
    }
  }

  Future<void> _doRegister({String? paypalOrderId}) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    final authProvider = context.read<AuthProvider>();
    final success = await authProvider.register(
      name: _nameController.text.trim(),
      email: _emailController.text.trim(),
      password: _passwordController.text,
      plan: _selectedPlan,
      paypalOrderId: paypalOrderId,
    );

    if (!mounted) return;

    if (success) {
      Navigator.pushReplacementNamed(context, '/home');
    } else {
      setState(() {
        _isLoading = false;
        _error = authProvider.error ?? 'Error al registrar';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.background,
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back),
        ),
        title: const Text('Crear cuenta'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Stepper
                _buildStepper(),
                const SizedBox(height: 24),
                
                // Error
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
                
                // Step 1: Datos personales
                if (_currentStep == 1) ...[
                  Text(
                    'Datos personales',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        TextFormField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: 'Nombre completo',
                            prefixIcon: const Icon(Icons.person_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.black.withOpacity(0.3),
                          ),
                          style: const TextStyle(color: Colors.white),
                          validator: Validators.validateName,
                        ),
                        const SizedBox(height: 16),
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
                        ),
                        const SizedBox(height: 16),
                        PasswordField(
                          controller: _passwordController,
                          label: 'Contraseña',
                          validator: Validators.validatePassword,
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Checkbox(
                              value: _acceptedTerms,
                              onChanged: (v) => setState(() => _acceptedTerms = v!),
                            ),
                            Expanded(
                              child: Text.rich(
                                TextSpan(
                                  text: 'Acepto los ',
                                  children: [
                                    TextSpan(
                                      text: 'Términos y Condiciones',
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                  ],
                                ),
                                style: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
                
                // Step 2: Selección de plan
                if (_currentStep == 2) ...[
                  Text(
                    'Elige tu plan',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildPlanCards(),
                ],
                
                // Step 3: Pago con PayPal
                if (_currentStep == 3) ...[
                  Text(
                    'Completa tu pago',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: theme.colorScheme.primary.withOpacity(0.3)),
                      color: theme.colorScheme.primary.withOpacity(0.05),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.payments, size: 32),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.green),
                              ),
                              child: const Text(
                                '🇲🇽 PayPal',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Plan ${AppConstants.planNames[_selectedPlan] ?? ''}',
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          '\$${AppConstants.prices[_selectedPlan] ?? 0} MXN',
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Placeholder para PayPal
                        Container(
                          height: 80,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: theme.colorScheme.outlineVariant.withOpacity(0.3)),
                            color: Colors.black.withOpacity(0.2),
                          ),
                          child: const Center(
                            child: Text(
                              'PayPal Button',
                              style: TextStyle(color: Colors.white54),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                
                const SizedBox(height: 24),
                
                // Navigation buttons
                Row(
                  children: [
                    if (_currentStep > 1)
                      Expanded(
                        child: GradientButton(
                          onPressed: () => setState(() => _currentStep--),
                          text: 'Atrás',
                          isOutlined: true,
                        ),
                      ),
                    if (_currentStep > 1) const SizedBox(width: 12),
                    Expanded(
                      child: GradientButton(
                        onPressed: _handleRegister,
                        isLoading: _isLoading,
                        text: _currentStep == 3 ? 'Pagar y registrarse' :
                              _currentStep == 2 && _selectedPlan != 'free' ? 'Continuar →' :
                              _currentStep == 2 ? 'Registrarse' :
                              'Siguiente →',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStepper() {
    final theme = Theme.of(context);
    const steps = ['Datos', 'Plan', 'Pago'];

    return Row(
      children: List.generate(steps.length, (index) {
        final isActive = index + 1 == _currentStep;
        final isCompleted = index + 1 < _currentStep;

        return Expanded(
          child: Column(
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isActive
                          ? theme.colorScheme.primary
                          : isCompleted
                              ? Colors.green
                              : theme.colorScheme.outlineVariant.withOpacity(0.3),
                    ),
                    child: Center(
                      child: isCompleted
                          ? const Icon(Icons.check, size: 16, color: Colors.white)
                          : Text(
                              '${index + 1}',
                              style: TextStyle(
                                color: isActive ? Colors.white : theme.colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                    ),
                  ),
                  if (index < steps.length - 1)
                    Expanded(
                      child: Container(
                        height: 2,
                        color: isCompleted
                            ? Colors.green
                            : theme.colorScheme.outlineVariant.withOpacity(0.3),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                steps[index],
                style: TextStyle(
                  fontSize: 11,
                  color: isActive
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Widget _buildPlanCards() {
    final plans = [
      {'id': 'free', 'name': 'Gratuito', 'price': '\$0', 'features': '3 proyectos · PDF'},
      {'id': 'pro', 'name': 'Pro', 'price': '\$350', 'features': '20 proyectos · IA · Soporte'},
      {'id': 'enterprise', 'name': 'Enterprise', 'price': '\$850', 'features': 'Ilimitado · API dedicada · 24/7'},
    ];

    return Column(
      children: plans.map((plan) {
        final isSelected = _selectedPlan == plan['id'];
        final isPopular = plan['id'] == 'pro';

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Theme.of(context).colorScheme.outlineVariant.withOpacity(0.3),
              width: isSelected ? 2 : 1,
            ),
            color: isSelected
                ? Theme.of(context).colorScheme.primary.withOpacity(0.05)
                : Colors.transparent,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => setState(() => _selectedPlan = plan['id']!),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                plan['name']!,
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                ),
                              ),
                              if (isPopular) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(20),
                                    color: Theme.of(context).colorScheme.primary,
                                  ),
                                  child: const Text(
                                    'POPULAR',
                                    style: TextStyle(
                                      fontSize: 9,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          Text(
                            plan['price']!,
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? Theme.of(context).colorScheme.primary
                                  : null,
                            ),
                          ),
                          Text(
                            plan['features']!,
                            style: TextStyle(
                              fontSize: 12,
                              color: Theme.of(context).colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Radio(
                      value: plan['id'],
                      groupValue: _selectedPlan,
                      onChanged: (v) => setState(() => _selectedPlan = v!),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}