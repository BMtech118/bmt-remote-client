// BMT Remote: tells a technician when a newer BMT Remote has been published
// and installs it in one click. Windows upgrades in place (the same silent
// install the auto-update uses); a Mac opens the new disk image.
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../../common.dart';
import 'bmt_toolbar_style.dart';

const _kBase = 'https://remote.bmtech.co.uk';

int _ver(String v) => v
    .split('.')
    .take(3)
    .fold(0, (a, n) => a * 10000 + (int.tryParse(n.split('+').first) ?? 0));

class BmtUpdateCard extends StatefulWidget {
  const BmtUpdateCard({Key? key}) : super(key: key);

  @override
  State<BmtUpdateCard> createState() => _BmtUpdateCardState();
}

class _BmtUpdateCardState extends State<BmtUpdateCard> {
  String? _latest;
  Map<String, dynamic> _downloads = {};
  double? _progress;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    try {
      final client = HttpClient();
      final res = await (await client.getUrl(Uri.parse('$_kBase/api/latest')))
          .close()
          .timeout(const Duration(seconds: 10));
      final body = await res.transform(utf8.decoder).join();
      client.close();
      if (res.statusCode != 200) return;
      final j = jsonDecode(body) as Map<String, dynamic>;
      final mine = (await PackageInfo.fromPlatform()).version;
      final latest = '${j['version'] ?? ''}';
      if (_ver(latest) > _ver(mine) && mounted) {
        setState(() {
          _latest = latest;
          _downloads = Map<String, dynamic>.from(j['downloads'] ?? {});
        });
      }
    } catch (_) {
      // No update card if the service can't be reached; nothing to report.
    }
  }

  Future<void> _install() async {
    final key = isWindows
        ? 'windows'
        : (Abi.current() == Abi.macosArm64 ? 'mac' : 'macintel');
    final path = _downloads[key];
    if (path is! String) return;
    setState(() {
      _progress = 0;
      _error = '';
    });
    try {
      final dir = await Directory.systemTemp.createTemp('bmt-remote-update');
      final file =
          File('${dir.path}/BMT-Remote-$_latest${isWindows ? '.exe' : '.dmg'}');
      final client = HttpClient();
      final res = await (await client.getUrl(Uri.parse('$_kBase$path'))).close();
      if (res.statusCode != 200) throw 'download returned ${res.statusCode}';
      final total = res.contentLength;
      var got = 0;
      final sink = file.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0 && mounted) setState(() => _progress = got / total);
      }
      await sink.close();
      client.close();
      if (isWindows) {
        await Process.start(file.path, ['--silent-install'],
            mode: ProcessStartMode.detached);
      } else {
        await Process.run('open', [file.path]);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _progress = null;
          _error = 'The update didn\'t download. Try again in a moment.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_latest == null) return const SizedBox.shrink();
    final busy = _progress != null;
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        color: const Color(0xff0f2a52),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff1f4c8f)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          BmtTb.icon('arrow-circle-up', const Color(0xff7fb2ff), size: 17),
          const SizedBox(width: 7),
          Text('BMT Remote $_latest is available',
              style: const TextStyle(
                  color: Color(0xffeef2f8),
                  fontWeight: FontWeight.w600,
                  fontSize: 13)),
        ]),
        const SizedBox(height: 4),
        Text(
            busy
                ? (_progress! >= 1
                    ? (isWindows
                        ? 'Installing. BMT Remote will restart.'
                        : 'Opened the installer. Drag BMT Remote to Applications.')
                    : 'Downloading ${(_progress! * 100).round()}%')
                : (_error.isNotEmpty ? _error : 'Update now to get the latest fixes.'),
            style: const TextStyle(
                color: Color(0xffb9c5d8), fontSize: 12, height: 1.4)),
        const SizedBox(height: 10),
        if (busy && _progress! < 1)
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: _progress,
              minHeight: 5,
              backgroundColor: const Color(0xff16263f),
              color: const Color(0xff7fb2ff),
            ),
          )
        else if (!busy)
          InkWell(
            borderRadius: BorderRadius.circular(8),
            onTap: _install,
            child: Container(
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: const Color(0xff078cf8),
                  borderRadius: BorderRadius.circular(8)),
              child: const Text('Update',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 13)),
            ),
          ),
      ]),
    );
  }
}
