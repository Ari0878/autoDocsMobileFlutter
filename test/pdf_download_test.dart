import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:AutoDocsAI/services/api_service.dart';
import 'package:AutoDocsAI/services/pdf_file_writer_io.dart';
import 'analysis_flow_test.dart' show FakeAdapter, jsonResponse;

class SavePicker extends FilePicker {
  SavePicker(this.path);
  final String? path;
  @override
  Future<String?> saveFile(
          {String? dialogTitle,
          String? fileName,
          String? initialDirectory,
          FileType type = FileType.any,
          List<String>? allowedExtensions,
          Uint8List? bytes,
          bool lockParentWindow = false}) async =>
      path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  final pdf = Uint8List.fromList(utf8.encode('%PDF-1.4\n%%EOF'));
  setUpAll(() async {
    FilePicker.platform = SavePicker(null);
    SharedPreferences.setMockInitialValues({});
    await api.init();
  });
  test('PDF bytes, selections and authentication survive download', () async {
    await api.setToken('test-token');
    api.dio.httpClientAdapter = FakeAdapter((options, stream) async {
      expect(options.responseType, ResponseType.bytes);
      expect(options.headers['Authorization'], 'Bearer test-token');
      expect(jsonDecode(options.queryParameters['selected']), {
        'functions': [2]
      });
      return ResponseBody.fromBytes(pdf, 200, headers: {
        'content-type': ['application/pdf']
      });
    });
    expect(
        await api.downloadProjectPdf('1', {
          'functions': [2]
        }),
        pdf);
  });
  test('HTML fallback is not saved as PDF', () async {
    api.dio.httpClientAdapter = FakeAdapter((options, stream) async =>
        ResponseBody.fromString('<html>fallback</html>', 200, headers: {
          'content-type': ['text/html']
        }));
    await expectLater(api.downloadProjectPdf('1', {}), throwsFormatException);
  });
  test('Server JSON errors returned as bytes remain readable', () async {
    api.dio.httpClientAdapter = FakeAdapter((options, stream) async =>
        jsonResponse({'error': 'Sin resultados de análisis'}, 404));
    try {
      await api.downloadProjectPdf('1', {});
      fail('Expected an HTTP error');
    } catch (e) {
      expect(ApiService.errorMessage(e), 'Sin resultados de análisis');
    }
  });
  test('Desktop save writes the exact PDF bytes to the selected file',
      () async {
    final directory =
        await Directory.systemTemp.createTemp('autodocs-pdf-test');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/document.pdf');
    final original = FilePicker.platform;
    addTearDown(() => FilePicker.platform = original);
    FilePicker.platform = SavePicker(file.path);
    expect(await savePdf('document.pdf', pdf), isTrue);
    expect(await file.readAsBytes(), pdf);
  });
  test('Cancelling save does not report success', () async {
    final original = FilePicker.platform;
    addTearDown(() => FilePicker.platform = original);
    FilePicker.platform = SavePicker(null);
    expect(await savePdf('document.pdf', pdf), isFalse);
  });
}
