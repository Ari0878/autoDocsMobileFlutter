import 'package:flutter/material.dart';

class AppConstants {
  // API
  static const String baseUrl = 'https://autodocs-s5jh.onrender.com';
  
  // Endpoints (con prefijo completo /api/auth como en Flask Blueprint)
  static const String register = '/api/auth/register';
  static const String login = '/api/auth/login';
  static const String logout = '/api/auth/logout';
  static const String forgotPassword = '/api/auth/forgot-password';
  static const String verifyCode = '/api/auth/verify-code';
  static const String resetPassword = '/api/auth/reset-password';
  static const String projects = '/api/projects';
  static const String analyzeProject = '/api/analysis/analyze';
  static const String exportDoc = '/api/export/export';
  
  // Storage keys
  static const String tokenKey = 'auth_token';
  static const String userKey = 'user_data';
  static const String themeKey = 'theme_mode';
  
  // Prices
  static const Map<String, int> prices = {
    'free': 0,
    'pro': 350,
    'enterprise': 850,
  };
  
  // Plan names
  static const Map<String, String> planNames = {
    'free': 'Gratuito',
    'pro': 'Pro',
    'enterprise': 'Enterprise',
  };

    static const Map<String, String> planDescriptions = {
    'free': 'Plan gratuito con funcionalidades básicas',
    'pro': 'Plan profesional con funcionalidades avanzadas',
    'enterprise': 'Plan empresarial con funcionalidades premium',
  };
}

class AppColors {
  // Dark theme
  static const Color background = Color(0xFF0F1418);
  static const Color surface = Color(0xFF1B2024);
  static const Color surfaceContainer = Color(0xFF252B2E);
  static const Color onSurface = Color(0xFFDEE3E8);
  static const Color onSurfaceVariant = Color(0xFFBDC8D1);
  static const Color primary = Color(0xFF39B2F8);
  static const Color secondary = Color(0xFFC0C1FF);
  static const Color tertiary = Color(0xFFFFC176);
  static const Color error = Color(0xFFFFB4AB);
  static const Color greenAccent = Color(0xFF10B981);
  static const Color outlineVariant = Color(0xFF3E484F);
  
  // Light theme
  static const Color lightBackground = Color(0xFFF1F5F9);
  static const Color lightSurface = Color(0xFFFFFFFF);
  static const Color lightOnSurface = Color(0xFF0F172A);
  static const Color lightOnSurfaceVariant = Color(0xFF334155);
  static const Color lightPrimary = Color(0xFF38BDF8);
  static const Color lightSecondary = Color(0xFF818CF8);
}

// class AppConstants {
//   // API
//   static const String baseUrl = 'https://autodocs-s5jh.onrender.com';
//   static const String apiVersion = 'api';
  
//   // Endpoints
//   static const String register = '/auth/register';
//   static const String login = '/auth/login';
//   static const String logout = '/auth/logout';
//   static const String forgotPassword = '/auth/forgot-password';
//   static const String verifyCode = '/auth/verify-code';
//   static const String resetPassword = '/auth/reset-password';
//   static const String projects = '/projects';
//   static const String analyzeProject = '/projects/analyze';
//   static const String exportDoc = '/projects/export';
  
//   // Storage keys
//   static const String tokenKey = 'auth_token';
//   static const String userKey = 'user_data';
//   static const String themeKey = 'theme_mode';  // <-- AGREGAR ESTO
  
//   // Prices
//   static const Map<String, int> prices = {
//     'free': 0,
//     'pro': 350,
//     'enterprise': 850,
//   };
  
//   // Plan names
//   static const Map<String, String> planNames = {
//     'free': 'Gratuito',
//     'pro': 'Pro',
//     'enterprise': 'Enterprise',
//   };
// }