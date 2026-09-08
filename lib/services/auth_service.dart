import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/auth_response.dart';
import '../models/user.dart';
import '../utils/constants.dart';
import 'api_service.dart';

class AuthService {
  final ApiService _api = ApiService();

  // ============================================================
  // REGISTRO
  // ============================================================

  Future<AuthResponse> register({
    required String name,
    required String email,
    required String password,
    required String plan,
    bool acceptedTerms = true,
    String? paypalOrderId,
  }) async {
    try {
      final response = await _api.post(
        '${AppConstants.baseUrl}/api/auth/register',
        data: {
          'name': name,
          'email': email,
          'password': password,
          'plan': plan,
          'accepted_terms': acceptedTerms,
          'payment_method': paypalOrderId != null ? 'paypal' : null,
          'paypal_order_id': paypalOrderId,
          'currency': 'MXN',
        },
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        final data = response.data;
        final token = data['token'];
        if (token != null) {
          await _api.setToken(token);
          final user = User.fromJson(data['user']);
          return AuthResponse(
            success: true,
            token: token,
            user: user,
          );
        }
        return AuthResponse(
          success: false,
          error: data['error'] ?? 'Error al registrar',
        );
      }

      return AuthResponse(
        success: false,
        error: response.data['error'] ?? 'Error al registrar',
      );
    } on DioException catch (e) {
      return AuthResponse(
        success: false,
        error: e.response?.data['error'] ?? 'Error de conexión',
      );
    } catch (e) {
      return AuthResponse(
        success: false,
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // LOGIN
  // ============================================================

  Future<AuthResponse> login(String email, String password) async {
    try {
      final response = await _api.post(
        '${AppConstants.baseUrl}/api/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;
        final token = data['token'];
        if (token != null) {
          await _api.setToken(token);
          final user = User.fromJson(data['user']);
          return AuthResponse(
            success: true,
            token: token,
            user: user,
          );
        }
        return AuthResponse(
          success: false,
          error: data['error'] ?? 'Error al iniciar sesión',
        );
      }

      return AuthResponse(
        success: false,
        error: response.data['error'] ?? 'Error al iniciar sesión',
      );
    } on DioException catch (e) {
      return AuthResponse(
        success: false,
        error: e.response?.data['error'] ?? 'Error de conexión',
      );
    } catch (e) {
      return AuthResponse(
        success: false,
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // OBTENER PERFIL DE USUARIO (NUEVO)
  // ============================================================

  Future<AuthResponse> getUserProfile() async {
    try {
      final response = await _api.get('/api/auth/me');
      
      if (response.statusCode == 200) {
        final userData = response.data;
        final user = User.fromJson(userData);
        return AuthResponse(
          success: true,
          user: user,
        );
      }
      
      return AuthResponse(
        success: false,
        error: response.data['error'] ?? 'Error al obtener perfil',
      );
    } on DioException catch (e) {
      return AuthResponse(
        success: false,
        error: e.response?.data['error'] ?? 'Error de conexión',
      );
    } catch (e) {
      return AuthResponse(
        success: false,
        error: e.toString(),
      );
    }
  }

  // ============================================================
  // RECUPERACIÓN DE CONTRASEÑA
  // ============================================================

  Future<AuthResponse> forgotPassword(String email) async {
    try {
      final response = await _api.post(
        '${AppConstants.baseUrl}/api/auth/forgot-password',
        data: {'email': email},
      );

      if (response.statusCode == 200) {
        return AuthResponse(
          success: true,
          error: response.data['message'],
        );
      }

      return AuthResponse(
        success: false,
        error: response.data['error'] ?? 'Error al enviar código',
      );
    } on DioException catch (e) {
      return AuthResponse(
        success: false,
        error: e.response?.data['error'] ?? 'Error de conexión',
      );
    }
  }

  Future<AuthResponse> verifyCode(String email, String code) async {
    try {
      final response = await _api.post(
        '${AppConstants.baseUrl}/api/auth/verify-code',
        data: {'email': email, 'code': code},
      );

      if (response.statusCode == 200) {
        return AuthResponse(success: true);
      }

      return AuthResponse(
        success: false,
        error: response.data['error'] ?? 'Código inválido',
      );
    } on DioException catch (e) {
      return AuthResponse(
        success: false,
        error: e.response?.data['error'] ?? 'Error de conexión',
      );
    }
  }

  Future<AuthResponse> resetPassword(
    String email,
    String code,
    String newPassword,
  ) async {
    try {
      final response = await _api.post(
        '${AppConstants.baseUrl}/api/auth/reset-password',
        data: {
          'email': email,
          'code': code,
          'new_password': newPassword,
        },
      );

      if (response.statusCode == 200) {
        return AuthResponse(success: true);
      }

      return AuthResponse(
        success: false,
        error: response.data['error'] ?? 'Error al cambiar contraseña',
      );
    } on DioException catch (e) {
      return AuthResponse(
        success: false,
        error: e.response?.data['error'] ?? 'Error de conexión',
      );
    }
  }

  // ============================================================
  // LOGOUT
  // ============================================================

  Future<void> logout() async {
    try {
      await _api.post('${AppConstants.baseUrl}/api/auth/logout');
    } catch (_) {}
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
  }
}