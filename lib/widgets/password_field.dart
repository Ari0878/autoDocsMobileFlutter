import 'package:flutter/material.dart';

class PasswordField extends StatefulWidget {
  final TextEditingController controller;
  final String label;
  final bool enabled;
  final String? Function(String?)? validator;
  final String? hintText;

  const PasswordField({
    super.key,
    required this.controller,
    required this.label,
    this.enabled = true,
    this.validator,
    this.hintText,
  });

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return TextFormField(
      controller: widget.controller,
      obscureText: _obscureText,
      enabled: widget.enabled,
      decoration: InputDecoration(
        labelText: widget.label,
        hintText: widget.hintText,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          onPressed: widget.enabled
              ? () => setState(() => _obscureText = !_obscureText)
              : null,
          icon: Icon(
            _obscureText ? Icons.visibility_off : Icons.visibility,
          ),
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        filled: true,
        fillColor: Colors.black.withOpacity(0.3),
      ),
      style: const TextStyle(color: Colors.white),
      validator: widget.validator ?? _defaultValidator,
    );
  }

  String? _defaultValidator(String? value) {
    if (value == null || value.isEmpty) {
      return 'Ingresa tu contraseña';
    }
    if (value.length < 8) {
      return 'Mínimo 8 caracteres';
    }
    return null;
  }
}