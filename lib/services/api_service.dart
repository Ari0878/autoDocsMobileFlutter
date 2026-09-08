import 'package:dio/dio.dart';
import 'package:dio_smart_retry/dio_smart_retry.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/constants.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;
  ApiService._internal();

  late Dio _dio;
  String? _token;
  bool _isInitialized = false;

  Future<void> init() async {
    if (_isInitialized) return;
    
    _dio = Dio(BaseOptions(
      baseUrl: AppConstants.baseUrl,
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 30),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));

    // Retry interceptor
    _dio.interceptors.add(
      RetryInterceptor(
        dio: _dio,
        retries: 3,
        retryDelays: const [
          Duration(seconds: 1),
          Duration(seconds: 2),
          Duration(seconds: 3),
        ],
      ),
    );

    // Token interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Token expirado - logout
            await _clearToken();
          }
          return handler.next(error);
        },
      ),
    );

    // Cargar token guardado
    await _loadToken();
    _isInitialized = true;
  }

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await init();
    }
  }

  Future<void> _loadToken() async {
    final prefs = await SharedPreferences.getInstance();
    _token = prefs.getString(AppConstants.tokenKey);
  }

  Future<void> setToken(String token) async {
    await _ensureInitialized();
    _token = token;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppConstants.tokenKey, token);
  }

  Future<void> _clearToken() async {
    _token = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppConstants.tokenKey);
    await prefs.remove(AppConstants.userKey);
  }

  Dio get dio => _dio;

  Future<Response> post(String path, {dynamic data, bool isMultipart = false}) async {
    await _ensureInitialized();
    return _dio.post(path, data: data);
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) async {
    await _ensureInitialized();
    return _dio.get(path, queryParameters: queryParams);
  }

  Future<Response> put(String path, {dynamic data}) async {
    await _ensureInitialized();
    return _dio.put(path, data: data);
  }

  Future<Response> delete(String path) async {
    await _ensureInitialized();
    return _dio.delete(path);
  }

  Future<Response> multipart(String path, FormData data) async {
    await _ensureInitialized();
    return _dio.post(path, data: data);
  }
}