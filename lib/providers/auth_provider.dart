import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import '../models/user.dart';
import '../models/auth_response.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';

class AuthProvider extends ChangeNotifier {
  final AuthService _authService = AuthService();
  
  User? _user;
  String? _token;
  bool _isLoading = false;
  String? _error;

  User? get user => _user;
  String? get token => _token;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get isAuthenticated => _token != null && _token!.isNotEmpty && _user != null;
  bool get isAdmin => _user?.isAdmin ?? false;

  AuthProvider() {
    _loadUser();
  }

  Future<void> _loadUser() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(AppConstants.tokenKey);
      
      final userJson = prefs.getString(AppConstants.userKey);
      if (userJson != null && userJson.isNotEmpty) {
        try {
          final Map<String, dynamic> data = Map<String, dynamic>.from(jsonDecode(userJson));
          _user = User.fromJson(data);
          print('👤 [Auth] Usuario cargado: ${_user?.name}, plan: ${_user?.plan}');
        } catch (e) {
          print('⚠️ [Auth] Error cargando usuario: $e');
          _user = null;
        }
      }
      notifyListeners();
    } catch (e) {
      print('⚠️ [Auth] Error en _loadUser: $e');
    }
  }

  Future<bool> register({
    required String name,
    required String email,
    required String password,
    required String plan,
    String? paypalOrderId,
  }) async {
    _setLoading(true);
    _clearError();

    try {
      final response = await _authService.register(
        name: name,
        email: email,
        password: password,
        plan: plan,
        paypalOrderId: paypalOrderId,
      );

      if (response.success && response.token != null && response.token!.isNotEmpty && response.user != null) {
        _token = response.token;
        _user = response.user;
        await _saveUser();
        print('✅ [Auth] Registro exitoso: ${_user?.email}, plan: ${_user?.plan}');
        _setLoading(false);
        return true;
      } else {
        _error = response.error ?? 'Error al registrar';
        print('❌ [Auth] Registro fallido: $_error');
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _error = e.toString();
      print('❌ [Auth] Excepción en registro: $e');
      _setLoading(false);
      return false;
    }
  }

  Future<bool> login(String email, String password) async {
    _setLoading(true);
    _clearError();

    try {
      print('🔑 [Auth] Intentando login: $email');
      final response = await _authService.login(email, password);

      if (response.success && response.token != null && response.token!.isNotEmpty && response.user != null) {
        _token = response.token;
        _user = response.user;
        await _saveUser();
        print('✅ [Auth] Login exitoso: ${_user?.email}, plan: ${_user?.plan}');
        _setLoading(false);
        return true;
      } else {
        _error = response.error ?? 'Credenciales inválidas';
        print('❌ [Auth] Login fallido: $_error');
        _setLoading(false);
        return false;
      }
    } catch (e) {
      _error = e.toString();
      print('❌ [Auth] Excepción en login: $e');
      _setLoading(false);
      return false;
    }
  }

  // NUEVO MÉTODO: Recargar datos del usuario desde el servidor
  Future<bool> refreshUser() async {
    try {
      if (_token == null || _token!.isEmpty) return false;
      
      final response = await _authService.getUserProfile();
      
      if (response.success && response.user != null) {
        _user = response.user;
        await _saveUser();
        print('🔄 [Auth] Usuario refrescado: ${_user?.name}, plan: ${_user?.plan}');
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ [Auth] Error refrescando usuario: $e');
      return false;
    }
  }

  Future<void> logout() async {
    try {
      await _authService.logout();
    } catch (_) {}
    
    _token = null;
    _user = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
    print('🗑️ [Auth] Sesión cerrada');
    notifyListeners();
  }

  Future<void> _saveUser() async {
    if (_user == null || _token == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AppConstants.tokenKey, _token!);
      await prefs.setString(AppConstants.userKey, jsonEncode(_user!.toJson()));
      print('💾 [Auth] Usuario guardado: ${_user?.name}, plan: ${_user?.plan}');
    } catch (e) {
      print('⚠️ [Auth] Error guardando usuario: $e');
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _clearError() {
    _error = null;
    notifyListeners();
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  void updateUser(User user) {
    _user = user;
    _saveUser();
    notifyListeners();
  }
}