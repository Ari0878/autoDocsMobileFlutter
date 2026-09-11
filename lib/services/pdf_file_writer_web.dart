// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;
import 'dart:async';
import 'dart:typed_data';

Future<bool> savePdf(String name, Uint8List bytes) async {
  final url =
      html.Url.createObjectUrlFromBlob(html.Blob([bytes], 'application/pdf'));
  final anchor = html.AnchorElement(href: url)..download = name;
  html.document.body!.append(anchor);
  anchor.click();
  anchor.remove();
  Timer(const Duration(minutes: 1), () => html.Url.revokeObjectUrl(url));
  return true;
}
