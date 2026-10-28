// BMT Remote: messages a technician sends from the console, shown on the
// customer's screen with a reply box. The conversation is identified by a
// token the server hands the app at check-in, so this window can only read
// and answer its own conversation.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const _chatUrl = 'https://remote.bmtech.co.uk/api/chat';
const _accent = Color(0xFF078CF8);

class _Msg {
  final int id;
  final bool fromTech;
  final String author;
  final String body;
  _Msg(this.id, this.fromTech, this.author, this.body);
}

class BmtPortalChat extends StatefulWidget {
  final String token;
  final VoidCallback? onClose;
  const BmtPortalChat({Key? key, required this.token, this.onClose})
      : super(key: key);

  @override
  State<BmtPortalChat> createState() => _BmtPortalChatState();
}

class _BmtPortalChatState extends State<BmtPortalChat> {
  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _timer;
  bool _ended = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  int get _last => _messages.isEmpty ? 0 : _messages.last.id;

  void _add(dynamic list) {
    for (final m in (list as List? ?? [])) {
      final id = m['id'] as int? ?? 0;
      if (id <= _last) continue;
      _messages.add(_Msg(id, m['sender'] == 'tech', (m['author'] ?? '').toString(),
          (m['body'] ?? '').toString()));
    }
  }

  Future<void> _poll() async {
    if (_ended) return;
    try {
      final res = await http
          .get(Uri.parse('$_chatUrl?t=${Uri.encodeQueryComponent(widget.token)}&after=$_last'))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 410 || res.statusCode == 403) {
        setState(() => _ended = true);
        return;
      }
      if (res.statusCode != 200) return;
      final before = _messages.length;
      _add(jsonDecode(res.body)['messages']);
      if (_messages.length != before) {
        setState(() {});
        _toBottom();
      }
    } catch (_) {}
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending || _ended) return;
    setState(() => _sending = true);
    try {
      final res = await http
          .post(Uri.parse(_chatUrl),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({'t': widget.token, 'body': text, 'after': _last}))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        _input.clear();
        _add(jsonDecode(res.body)['messages']);
        _toBottom();
      } else if (res.statusCode == 410) {
        _ended = true;
      }
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            height: 52,
            color: const Color(0xFF0E151F),
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: Row(children: [
              const Icon(Icons.chat_bubble_outline, color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Message from BM Technologies',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14)),
              ),
              if (widget.onClose != null)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white70, size: 18),
                  onPressed: widget.onClose,
                ),
            ]),
          ),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.all(14),
              itemCount: _messages.length,
              itemBuilder: (context, i) {
                final m = _messages[i];
                return Align(
                  alignment: m.fromTech ? Alignment.centerLeft : Alignment.centerRight,
                  child: Container(
                    constraints: const BoxConstraints(maxWidth: 280),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: m.fromTech ? const Color(0xFFEEF3F8) : _accent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(m.body,
                            style: TextStyle(
                                fontSize: 13.5,
                                color: m.fromTech ? const Color(0xFF142B4A) : Colors.white)),
                        const SizedBox(height: 3),
                        Text(m.fromTech ? (m.author.isEmpty ? 'BM Technologies' : m.author) : 'You',
                            style: TextStyle(
                                fontSize: 10.5,
                                color: m.fromTech ? const Color(0xFF6F8096) : Colors.white70)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          if (_ended)
            const Padding(
              padding: EdgeInsets.all(14),
              child: Text('This conversation has ended.',
                  style: TextStyle(color: Color(0xFF6F8096))),
            )
          else
            Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    autofocus: true,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: const InputDecoration(
                      hintText: 'Type a reply',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _accent),
                  onPressed: _sending ? null : _send,
                  child: const Text('Send', style: TextStyle(color: Colors.white)),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}

/// For the session download that is running uninstalled: watch for portal
/// messages and pop the chat up over the app when one arrives.
class BmtPortalChatWatcher {
  static Timer? _timer;
  static int _seen = 0;
  static bool _open = false;

  static void start(String token, int last, GlobalKey<NavigatorState> navigator) {
    _seen = last;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 15), (_) async {
      if (_open) return;
      try {
        final res = await http
            .get(Uri.parse('$_chatUrl?t=${Uri.encodeQueryComponent(token)}&after=$_seen'))
            .timeout(const Duration(seconds: 10));
        if (res.statusCode != 200) return;
        final list = jsonDecode(res.body)['messages'] as List? ?? [];
        final fromTech = list.where((m) => m['sender'] == 'tech').toList();
        if (fromTech.isEmpty) return;
        _seen = list.map((m) => m['id'] as int? ?? 0).fold(_seen, (a, b) => b > a ? b : a);
        final context = navigator.currentContext;
        if (context == null) return;
        _open = true;
        await showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => Dialog(
            clipBehavior: Clip.antiAlias,
            child: SizedBox(
              width: 380,
              height: 480,
              child: BmtPortalChat(token: token, onClose: () => Navigator.of(ctx).pop()),
            ),
          ),
        );
        _open = false;
      } catch (_) {
        _open = false;
      }
    });
  }

  static bool get supported => Platform.isWindows || Platform.isMacOS;
}
