// BMT Remote: tells remote.bmtech.co.uk which computer is running for a
// support session, so the technician's console shows it ready to connect
// without the customer reading out an ID.
//
// The session code arrives one of two ways:
//  - Windows: the download is named BMT-Remote-<CODE>.exe. The portable
//    launcher passes that original file name in RUSTDESK_APPNAME.
//  - Mac (installed): the session page opens bmtremote://bmt-session/<CODE>.
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'models/platform_model.dart';

const _checkinUrl = 'https://remote.bmtech.co.uk/api/checkin';
final _codeInName = RegExp(r'BMT-Remote-([A-Z2-9]{6})', caseSensitive: false);
final _validCode = RegExp(r'^[A-Z2-9]{6}$');

/// The session code in the name this app was launched from, if any.
String? sessionCodeFromLaunch() {
  final name = Platform.environment['RUSTDESK_APPNAME'] ?? Platform.resolvedExecutable;
  final file = name.split(RegExp(r'[\\/]')).last;
  return _codeInName.firstMatch(file)?.group(1)?.toUpperCase();
}

/// The session code in a bmtremote://bmt-session/<CODE> link, if it is one.
String? sessionCodeFromUri(Uri? uri) {
  if (uri == null || uri.host != 'bmt-session' || uri.pathSegments.isEmpty) return null;
  final code = uri.pathSegments.first.toUpperCase();
  return _validCode.hasMatch(code) ? code : null;
}

bool _sent = false;

/// Reports this computer's ID for [code]. The ID only exists once the app has
/// registered with our server, and the server only accepts an ID it knows,
/// so this retries for about a minute. Never throws.
Future<void> bmtCheckIn(String code) async {
  if (_sent) return;
  for (var attempt = 0; attempt < 12; attempt++) {
    try {
      final id = await bind.mainGetMyId();
      if (id.isNotEmpty) {
        final res = await http
            .post(Uri.parse(_checkinUrl),
                headers: {'Content-Type': 'application/json'},
                body: jsonEncode({'code': code, 'id': id}))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode == 200) {
          _sent = true;
          return;
        }
        // The code has ended or never existed: nothing more to do.
        if (res.statusCode == 404 || res.statusCode == 410) return;
      }
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 5));
  }
}
