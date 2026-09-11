import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:AutoDocsAI/services/api_service.dart';
import 'package:AutoDocsAI/providers/theme_provider.dart';
import 'package:AutoDocsAI/screens/project_detail_screen.dart';

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.respond);
  final Future<ResponseBody> Function(RequestOptions, Stream<Uint8List>?)
      respond;
  int calls = 0;
  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? stream,
      Future<void>? cancelFuture) {
    calls++;
    return respond(options, stream);
  }

  @override
  void close({bool force = false}) {}
}

ResponseBody jsonResponse(Object data, [int status = 200]) =>
    ResponseBody.fromString(jsonEncode(data), status, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType]
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });

  test('ZIP reaches HTTP transport with filename, bytes and multipart boundary',
      () async {
    final adapter = FakeAdapter((options, stream) async {
      expect(options.contentType, startsWith('multipart/form-data; boundary='));
      final bytes = await stream!.expand((chunk) => chunk).toList();
      final body = utf8.decode(bytes);
      expect(body, contains('name="file"; filename="project.zip"'));
      expect(body, contains('PK-test-archive'));
      return jsonResponse({'id': '1'}, 201);
    });
    api.dio.httpClientAdapter = adapter;
    await api.post('/api/projects/',
        data: FormData.fromMap({
          'name': 'Example',
          'file': MultipartFile.fromBytes(utf8.encode('PK-test-archive'),
              filename: 'project.zip'),
        }));
    expect(adapter.calls, 1);
  });

  test('POST is not retried on server failure', () async {
    final adapter = FakeAdapter((options, stream) async =>
        jsonResponse({'error': 'Worker unavailable'}, 503));
    api.dio.httpClientAdapter = adapter;
    await expectLater(
        api.post('/api/projects/',
            data: {'github_url': 'https://github.com/a/b'}),
        throwsA(isA<DioException>()));
    expect(adapter.calls, 1);
  });

  test('Creation explicitly starts the backend analysis using its returned id',
      () async {
    final paths = <String>[];
    api.dio.httpClientAdapter = FakeAdapter((options, stream) async {
      paths.add(options.path);
      if (options.path == '/api/projects/') {
        expect(options.receiveTimeout, const Duration(minutes: 3));
        return jsonResponse({'id': 'created-project'}, 201);
      }
      return jsonResponse({'project_id': 'created-project'}, 202);
    });
    await api.createAndAnalyzeProject(FormData.fromMap({
      'github_url': 'https://github.com/stsus20/manofactura_ia.git',
    }));
    expect(paths, ['/api/projects/', '/api/analysis/created-project/start']);
  });

  test('A 201 with clone failure does not start analysis or report success',
      () async {
    final adapter = FakeAdapter((options, stream) async =>
        jsonResponse({'id': '1', 'error': 'Clone failed'}, 201));
    api.dio.httpClientAdapter = adapter;
    await expectLater(
        api.createAndAnalyzeProject(FormData()),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('Clone failed'))));
    expect(adapter.calls, 1);
  });

  test('Failed start preserves the created project and explains recovery',
      () async {
    final paths = <String>[];
    api.dio.httpClientAdapter = FakeAdapter((options, stream) async {
      paths.add(options.path);
      return options.path == '/api/projects/'
          ? jsonResponse({'id': '1'}, 201)
          : jsonResponse({'error': 'Start failed'}, 503);
    });
    await expectLater(
        api.createAndAnalyzeProject(FormData()),
        throwsA(isA<StateError>()
            .having((e) => e.message, 'message', contains('ya se creó'))));
    expect(paths, ['/api/projects/', '/api/analysis/1/start']);
  });
  testWidgets('Failed analysis leaves loading state and shows server reason',
      (tester) async {
    final adapter = FakeAdapter((options, stream) async => jsonResponse({
          'id': '1',
          'name': 'Example',
          'status': 'error',
          'error_message': 'Analysis worker exceeded its deadline',
        }));
    api.dio.httpClientAdapter = adapter;
    await tester.pumpWidget(ChangeNotifierProvider(
      create: (_) => ThemeProvider(),
      child: const MaterialApp(home: ProjectDetailScreen(projectId: '1')),
    ));
    await tester.pumpAndSettle();
    expect(find.textContaining('Analysis worker exceeded its deadline'),
        findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    await tester.pump(const Duration(seconds: 15));
    expect(adapter.calls, 1);
  });
}
