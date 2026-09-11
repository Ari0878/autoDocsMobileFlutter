import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
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
        retryEvaluator: (error, attempt) async =>
            const ['GET', 'HEAD'].contains(error.requestOptions.method) &&
            await RetryInterceptor.defaultRetryEvaluator(error, attempt),
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
          debugPrint('[API] ${options.method} ${options.uri.path}');
          if (_token != null) {
            options.headers['Authorization'] = 'Bearer $_token';
          }
          return handler.next(options);
        },
        onError: (error, handler) async {
          debugPrint('[API] ${error.requestOptions.method} '
              '${error.requestOptions.uri.path}: ${error.type.name} '
              'HTTP ${error.response?.statusCode ?? "sin respuesta"}');
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

  Future<Response> post(String path,
      {dynamic data,
      bool isMultipart = false,
      Duration? receiveTimeout}) async {
    await _ensureInitialized();
    return _dio.post(path,
        data: data,
        options: Options(
          contentType: isMultipart || data is FormData
              ? 'multipart/form-data'
              : Headers.jsonContentType,
          sendTimeout: const Duration(minutes: 2),
          receiveTimeout: receiveTimeout,
        ));
  }

  Future<Response> get(String path, {Map<String, dynamic>? queryParams}) async {
    await _ensureInitialized();
    return _dio.get(path, queryParameters: queryParams);
  }

  Future<Uint8List> downloadProjectPdf(
      String projectId, Map<String, List<int>> selections) async {
    await _ensureInitialized();
    try {
      final response = await _dio.get<List<int>>(
        '/api/export/${Uri.encodeComponent(projectId)}/pdf',
        queryParameters: {'selected': jsonEncode(selections)},
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(minutes: 3),
          headers: {'Accept': 'application/pdf'},
          extra: {'ro_disable_retry': true},
        ),
      );
      final bytes = response.data ?? [];
      if (bytes.length < 5 ||
          ascii.decode(bytes.take(5).toList(), allowInvalid: true) != '%PDF-') {
        throw const FormatException('El servidor no generó un PDF válido. '
            'Puede haber devuelto HTML como alternativa; revisa el generador PDF del backend.');
      }
      return Uint8List.fromList(bytes);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is List<int>) {
        try {
          e.response?.data = jsonDecode(utf8.decode(data));
        } on FormatException {
          // Keep the HTTP error when the server did not return JSON.
        }
      }
      rethrow;
    }
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
    return post(path, data: data, isMultipart: true);
  }

  Future<Response> createAndAnalyzeProject(FormData data) async {
    // The server clones GitHub synchronously (up to 120 seconds).
    final response = await post('/api/projects/',
        data: data, receiveTimeout: const Duration(minutes: 3));
    final body = response.data;
    if (body is! Map || body['id'] == null) {
      throw StateError('El servidor no devolvió el identificador del proyecto. '
          'Actualiza la lista antes de volver a crearlo.');
    }
    final id = body['id'].toString();
    if (body['error'] != null) {
      throw StateError('El proyecto se creó con errores: ${body['error']}');
    }
    try {
      await startAnalysis(id);
    } catch (e) {
      throw StateError('El proyecto ya se creó, pero no se confirmó el inicio '
          'del análisis: ${errorMessage(e)} '
          'Abre el proyecto desde la lista para verificarlo o reintentar el análisis.');
    }
    return response;
  }

  Future<Response> startAnalysis(String projectId) =>
      post('/api/analysis/${Uri.encodeComponent(projectId)}/start');

  static String errorMessage(Object error) {
    if (error is DioException) {
      final data = error.response?.data;
      if (data is Map) {
        final message =
            data['error_message'] ?? data['error'] ?? data['message'];
        if (message is String && message.isNotEmpty) return message;
      }
      if (error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return 'El servidor no respondió a tiempo. Actualiza los proyectos '
            'para comprobar si se creó antes de volver a enviarlo.';
      }
      return 'No se pudo completar la solicitud '
          '(HTTP ${error.response?.statusCode ?? "sin respuesta"}, ${error.type.name}).';
    }
    return error.toString();
  }
}
