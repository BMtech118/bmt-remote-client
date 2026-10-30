// BMT Remote: drag files from the technician's computer onto the remote screen
// and they are saved to the Desktop of whoever is signed in on the remote
// computer. The file goes to the BMT Remote service with the pass issued at
// Connect, the computer fetches it once and the service deletes its copy.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter/material.dart';

import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'bmt_toolbar_style.dart';

const _kBase = 'https://remote.bmtech.co.uk';

class _Drop {
  final String name;
  double progress = 0; // upload, 0..1
  String state = 'uploading'; // uploading, saving, done, failed
  String message = '';
  _Drop(this.name);
}

class BmtDropZone extends StatefulWidget {
  final FFI ffi;
  final String id;
  final Widget child;
  const BmtDropZone(
      {Key? key, required this.ffi, required this.id, required this.child})
      : super(key: key);

  @override
  State<BmtDropZone> createState() => _BmtDropZoneState();
}

class _BmtDropZoneState extends State<BmtDropZone> {
  bool _over = false;
  final List<_Drop> _drops = [];

  String get _pass => bind.mainGetLocalOption(key: 'bmt-term-${widget.id}');
  String get _host {
    final h = widget.ffi.ffiModel.pi.hostname;
    return h.isNotEmpty ? h : widget.id;
  }

  void _update() {
    if (mounted) setState(() {});
  }

  void _finish(_Drop d, String state, String message) {
    d.state = state;
    d.message = message;
    _update();
    Timer(Duration(seconds: state == 'done' ? 6 : 12), () {
      _drops.remove(d);
      _update();
    });
  }

  Future<void> _send(String path) async {
    final file = File(path);
    final name = path.split(Platform.pathSeparator).last;
    final d = _Drop(name);
    _drops.add(d);
    _update();
    if (FileSystemEntity.isDirectorySync(path)) {
      return _finish(d, 'failed', 'Folders can\'t be dropped. Zip it first.');
    }
    final pass = _pass;
    if (pass.isEmpty) {
      return _finish(
          d, 'failed', 'Reconnect from the BMT Remote console to send files.');
    }
    final client = HttpClient();
    try {
      final length = await file.length();
      final req = await client.postUrl(Uri.parse(
          '$_kBase/api/app-drop/${widget.id}?t=${Uri.encodeQueryComponent(pass)}'
          '&name=${Uri.encodeQueryComponent(name)}'));
      req.contentLength = length;
      req.headers.contentType = ContentType.binary;
      var sent = 0;
      await req.addStream(file.openRead().map((chunk) {
        sent += chunk.length;
        d.progress = length == 0 ? 1 : sent / length;
        _update();
        return chunk;
      }));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      final j = jsonDecode(body.isEmpty ? '{}' : body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        return _finish(d, 'failed', '${j['error'] ?? 'Upload failed (${res.statusCode}).'}');
      }
      d.state = 'saving';
      d.progress = 1;
      _update();
      await _wait(d, j['cmd'] as int, pass);
    } catch (_) {
      _finish(d, 'failed', 'The upload didn\'t finish. Check your connection.');
    } finally {
      client.close();
    }
  }

  Future<void> _wait(_Drop d, int cmd, String pass) async {
    final deadline = DateTime.now().add(const Duration(minutes: 16));
    while (DateTime.now().isBefore(deadline) && mounted) {
      await Future.delayed(const Duration(milliseconds: 1500));
      final client = HttpClient();
      try {
        final req = await client.getUrl(Uri.parse(
            '$_kBase/api/app-drop/${widget.id}/$cmd?t=${Uri.encodeQueryComponent(pass)}'));
        final res = await req.close();
        final j = jsonDecode(await res.transform(utf8.decoder).join())
            as Map<String, dynamic>;
        final status = j['status'];
        if (status == 'done') {
          return _finish(d, 'done', 'Saved to the Desktop on $_host');
        }
        if (status == 'failed' || status == 'timeout') {
          final out = '${j['output'] ?? ''}'.trim().split('\n').last;
          return _finish(d, 'failed',
              out.isNotEmpty ? out : 'The computer couldn\'t save the file.');
        }
      } catch (_) {
        // Keep waiting; a blip shouldn't fail the drop.
      } finally {
        client.close();
      }
    }
    _finish(d, 'failed', 'The computer didn\'t pick the file up in time.');
  }

  Widget _card(_Drop d) {
    final failed = d.state == 'failed';
    final done = d.state == 'done';
    final label = {
          'uploading': 'Sending to $_host',
          'saving': 'Saving on $_host',
        }[d.state] ??
        d.message;
    return Container(
      width: 320,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: BmtTb.menuShadow,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: failed ? BmtTb.redSoft : BmtTb.blueSoft,
              borderRadius: BorderRadius.circular(8)),
          alignment: Alignment.center,
          child: BmtTb.icon(
              failed
                  ? 'x'
                  : done
                      ? 'check-circle'
                      : 'file-arrow-up',
              failed ? BmtTb.red : BmtTb.blue,
              size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(d.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: BmtTb.ink, fontSize: 13, fontWeight: FontWeight.w500)),
            const SizedBox(height: 2),
            Text(label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    color: failed ? BmtTb.red : BmtTb.ink3, fontSize: 11.5)),
            if (!failed && !done) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: d.state == 'saving' ? null : d.progress,
                  minHeight: 5,
                  backgroundColor: const Color(0xfff4f5f7),
                  color: BmtTb.blue,
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _over = true),
      onDragExited: (_) => setState(() => _over = false),
      onDragDone: (detail) {
        setState(() => _over = false);
        for (final f in detail.files) {
          _send(f.path);
        }
      },
      child: Stack(children: [
        widget.child,
        if (_over)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(
                margin: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0x330a53c4),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: BmtTb.blue, width: 2),
                ),
                alignment: Alignment.center,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: BmtTb.menuShadow),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    BmtTb.icon('file-arrow-up', BmtTb.blue, size: 22),
                    const SizedBox(width: 10),
                    Text('Drop to save on the Desktop of $_host',
                        style: const TextStyle(
                            color: BmtTb.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w500)),
                  ]),
                ),
              ),
            ),
          ),
        if (_drops.isNotEmpty)
          Positioned(
            right: 16,
            bottom: 16,
            child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _drops.map(_card).toList()),
          ),
      ]),
    );
  }
}
