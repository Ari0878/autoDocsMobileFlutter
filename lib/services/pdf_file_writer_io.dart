import 'dart:io';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';

Future<bool> savePdf(String name, Uint8List bytes) async {
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Guardar documentación PDF',
    fileName: name,
    type: FileType.custom,
    allowedExtensions: ['pdf'],
    bytes: bytes,
  );
  if (path == null) return false;
  // Android/iOS FilePicker saves the supplied bytes through the system picker.
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return true;
}
