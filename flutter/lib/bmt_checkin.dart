// BMT Remote: tells remote.bmtech.co.uk which computer is running for a
// support session, so the technician's console shows it ready to connect
// without the customer reading out an ID.
//
// The session code arrives one of two ways:
//  - Windows: the download is named BMT-Remote-<CODE>.exe. The portable
//    launcher passes that original file name in RUSTDESK_APPNAME.
//  - Mac (installed): the session page opens bmtremote://bmt-session/<CODE>.
//
// After checking in it keeps sending a heartbeat, so the console can say
// whether the app is still running. On Windows the session app also asks to
// be reopened at the next sign-in, so a support session survives a reboot;
// that entry goes when the app is closed or the technician ends the session.
import 'dart:async';
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

// RunOnce: Windows deletes the entry as it runs it, and the reopened app adds
// it again, so it only lasts while the session app keeps running.
const _autostartKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\RunOnce';
const _autostartValue = 'BMTRemoteSession';

bool _sent = false;
Timer? _heartbeat;

Future<http.Response> _post(String code, String id) => http
    .post(Uri.parse(_checkinUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'code': code, 'id': id, 'hb': 1}))
    .timeout(const Duration(seconds: 10));

/// Reports this computer's ID for [code]. The ID only exists once the app has
/// registered with our server, and the server only accepts an ID it knows,
/// so this retries for about three minutes (longer after a reboot, while the
/// network comes up). Never throws.
Future<void> bmtCheckIn(String code) async {
  if (_sent) return;
  for (var attempt = 0; attempt < 36; attempt++) {
    try {
      final id = await bind.mainGetMyId();
      if (id.isNotEmpty) {
        final res = await _post(code, id);
        if (res.statusCode == 200) {
          _sent = true;
          await _setAutostart();
          _heartbeat = Timer.periodic(const Duration(seconds: 60), (_) => _beat(code, id));
          return;
        }
        if (res.statusCode == 410) return await _sessionEnded();
        // The code never existed: nothing more to do.
        if (res.statusCode == 404) return;
      }
    } catch (_) {}
    await Future.delayed(const Duration(seconds: 5));
  }
}

Future<void> _beat(String code, String id) async {
  try {
    final res = await _post(code, id);
    if (res.statusCode == 410) await _sessionEnded();
  } catch (_) {}
}

/// The technician ended the session: nothing more for this app to do.
Future<void> _sessionEnded() async {
  await bmtSessionAppClosing();
  exit(0);
}

/// Reopen this session app at the next Windows sign-in. Only the portable
/// session download has a launcher path; an installed app never does this.
Future<void> _setAutostart() async {
  final launcher = Platform.environment['BMT_LAUNCHER_PATH'] ?? '';
  if (!Platform.isWindows || launcher.isEmpty || sessionCodeFromLaunch() == null) return;
  try {
    await Process.run('reg', ['add', _autostartKey, '/v', _autostartValue, '/t', 'REG_SZ', '/d', '"$launcher"', '/f']);
  } catch (_) {}
}

/// Called as the app closes: stop the heartbeat and don't reopen after a reboot.
Future<void> bmtSessionAppClosing() async {
  _heartbeat?.cancel();
  if (!Platform.isWindows || !_sent) return;
  try {
    await Process.run('reg', ['delete', _autostartKey, '/v', _autostartValue, '/f']);
  } catch (_) {}
}
