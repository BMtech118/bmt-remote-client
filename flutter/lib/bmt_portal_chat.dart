// BMT Remote: messages a technician sends from the console, shown on the
// customer's screen with a reply box. The conversation is identified by a
// token the server hands the app at check-in, so this window can only read
// and answer its own conversation. Layout follows the approved mock-up
// (bmt-remote _design-refs/chat-mockup-approved-2026-10-28.png).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

const _chatUrl = 'https://remote.bmtech.co.uk/api/chat';

const _navy = Color(0xFF0E151F);
const _blue = Color(0xFF078CF8);
const _paper = Color(0xFFF7F9FC);
const _card = Color(0xFFFDFEFF);
const _text = Color(0xFF142B4A);
const _muted = Color(0xFF6B7C93);
const _rule = Color(0xFFE3E9F1);
const _onBlue = Color(0xFFFBFDFF);
const _soft = Color(0xFFA3B2C5);

class _Msg {
  final int id;
  final bool fromTech;
  final String author;
  final String body;
  final DateTime at;
  _Msg(this.id, this.fromTech, this.author, this.body, this.at);
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return 'BM';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

String _hhmm(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

class BmtPortalChat extends StatefulWidget {
  final String token;
  final VoidCallback? onClose;

  /// Called when a new technician message arrives, to bring the window forward.
  final VoidCallback? onTechMessage;

  const BmtPortalChat(
      {Key? key, required this.token, this.onClose, this.onTechMessage})
      : super(key: key);

  @override
  State<BmtPortalChat> createState() => _BmtPortalChatState();
}

class _BmtPortalChatState extends State<BmtPortalChat> {
  final _messages = <_Msg>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _focus = FocusNode();
  Timer? _timer;
  bool _ended = false;
  bool _sending = false;
  String? _typing;
  int _seenUpTo = 0;
  DateTime _lastTypingPing = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    _focus.onKeyEvent = (node, event) {
      // Enter sends; Shift+Enter keeps the new line.
      if (event is KeyDownEvent &&
          event.logicalKey == LogicalKeyboardKey.enter &&
          !HardwareKeyboard.instance.isShiftPressed) {
        _send();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    };
    _input.addListener(_typingPing);
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _input.dispose();
    _scroll.dispose();
    _focus.dispose();
    super.dispose();
  }

  int get _last => _messages.isEmpty ? 0 : _messages.last.id;

  String get _techName {
    for (final m in _messages.reversed) {
      if (m.fromTech && m.author.isNotEmpty) return m.author;
    }
    return _typing ?? '';
  }

  bool _add(dynamic list) {
    var techArrived = false;
    for (final m in (list as List? ?? [])) {
      final id = m['id'] as int? ?? 0;
      if (id <= _last) continue;
      final fromTech = m['sender'] == 'tech';
      techArrived |= fromTech;
      _messages.add(_Msg(
          id,
          fromTech,
          (m['author'] ?? '').toString(),
          (m['body'] ?? '').toString(),
          DateTime.tryParse((m['at'] ?? '').toString())?.toLocal() ??
              DateTime.now()));
    }
    return techArrived;
  }

  void _apply(Map<String, dynamic> out) {
    final techArrived = _add(out['messages']);
    _typing = out['typing'] is String ? out['typing'] as String : null;
    _seenUpTo = (out['seenUpTo'] as int?) ?? _seenUpTo;
    if (techArrived) widget.onTechMessage?.call();
  }

  Future<void> _poll() async {
    if (_ended) return;
    try {
      final res = await http
          .get(Uri.parse(
              '$_chatUrl?t=${Uri.encodeQueryComponent(widget.token)}&after=$_last'))
          .timeout(const Duration(seconds: 10));
      if (!mounted) return;
      if (res.statusCode == 410 || res.statusCode == 403) {
        setState(() => _ended = true);
        return;
      }
      if (res.statusCode != 200) return;
      final before = _messages.length;
      final wasTyping = _typing != null;
      setState(() => _apply(jsonDecode(res.body)));
      if (_messages.length != before || (_typing != null && !wasTyping)) {
        _toBottom();
      }
    } catch (_) {}
  }

  void _typingPing() {
    if (_input.text.trim().isEmpty ||
        DateTime.now().difference(_lastTypingPing).inMilliseconds < 2500) {
      return;
    }
    _lastTypingPing = DateTime.now();
    http
        .post(Uri.parse('$_chatUrl/typing'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({'t': widget.token}))
        .timeout(const Duration(seconds: 10))
        .catchError((_) => http.Response('', 0));
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
        _lastTypingPing = DateTime.fromMillisecondsSinceEpoch(0);
        _apply(jsonDecode(res.body));
        _toBottom();
      } else if (res.statusCode == 410) {
        _ended = true;
      }
    } catch (_) {}
    if (mounted) setState(() => _sending = false);
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.animateTo(_scroll.position.maxScrollExtent,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut);
        }
      });

  Widget _avatar(String name, double size) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: const BoxDecoration(color: _blue, shape: BoxShape.circle),
        child: Text(_initials(name),
            style: TextStyle(
                color: _onBlue,
                fontWeight: FontWeight.w600,
                fontSize: size < 30 ? size * 0.46 : size * 0.38)),
      );

  Widget _header() {
    final name = _techName;
    return Container(
      color: _navy,
      padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
      child: Row(children: [
        _avatar(name.isEmpty ? 'BM' : name, 36),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('BM Technologies support',
                  style: TextStyle(
                      color: Color(0xFFE6EDF6),
                      fontWeight: FontWeight.w600,
                      fontSize: 14.5)),
              if (name.isNotEmpty)
                Text(name, style: const TextStyle(color: _soft, fontSize: 12)),
            ],
          ),
        ),
        if (widget.onClose != null)
          IconButton(
            tooltip: 'Close',
            icon: const Icon(Icons.close, color: _soft, size: 19),
            onPressed: widget.onClose,
          ),
      ]),
    );
  }

  /// Messages in runs by sender: name and time above a technician's run,
  /// time and "Seen" below the customer's.
  List<Widget> _groups() {
    final out = <Widget>[
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Center(
            child: Text('Today', style: TextStyle(color: _muted, fontSize: 11))),
      ),
    ];
    var i = 0;
    while (i < _messages.length) {
      final run = <_Msg>[_messages[i]];
      while (i + run.length < _messages.length &&
          _messages[i + run.length].fromTech == run.first.fromTech) {
        run.add(_messages[i + run.length]);
      }
      i += run.length;
      out.add(run.first.fromTech ? _techRun(run) : _myRun(run));
    }
    if (_typing != null) out.add(_typingRow(_typing!));
    return out;
  }

  Widget _bubble(_Msg m, {required bool mine, required bool last}) =>
      Container(
        constraints: const BoxConstraints(maxWidth: 262),
        margin: const EdgeInsets.only(bottom: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: mine ? _blue : _card,
          border: mine ? null : Border.all(color: _rule),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(14),
            topRight: const Radius.circular(14),
            bottomLeft: Radius.circular(!mine && last ? 4 : 14),
            bottomRight: Radius.circular(mine && last ? 4 : 14),
          ),
        ),
        child: SelectableText(m.body,
            style: TextStyle(fontSize: 13.5, height: 1.4, color: mine ? _onBlue : _text)),
      );

  Widget _techRun(List<_Msg> run) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _avatar(run.first.author, 26),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(left: 2, bottom: 3),
                  child: Text(
                      '${run.first.author.isEmpty ? 'BM Technologies' : run.first.author} · ${_hhmm(run.first.at)}',
                      style: const TextStyle(color: _muted, fontSize: 11.5)),
                ),
                for (var k = 0; k < run.length; k++)
                  _bubble(run[k], mine: false, last: k == run.length - 1),
              ],
            ),
          ],
        ),
      );

  Widget _myRun(List<_Msg> run) {
    final seen = run.last.id <= _seenUpTo;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var k = 0; k < run.length; k++)
            _bubble(run[k], mine: true, last: k == run.length - 1),
          Padding(
            padding: const EdgeInsets.only(top: 1, right: 4),
            child: Text('${_hhmm(run.last.at)}${seen ? ' · Seen' : ''}',
                style: const TextStyle(color: _muted, fontSize: 10.5)),
          ),
        ],
      ),
    );
  }

  Widget _typingRow(String name) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          _avatar(name, 26),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
            decoration: BoxDecoration(
              color: _card,
              border: Border.all(color: _rule),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(14),
                topRight: Radius.circular(14),
                bottomRight: Radius.circular(14),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: const _TypingDots(),
          ),
          const SizedBox(width: 8),
          Text('${name.split(' ').first} is typing…',
              style: const TextStyle(color: _muted, fontSize: 11.5)),
        ]),
      );

  Widget _composer() {
    if (_ended) {
      return Container(
        color: _card,
        padding: const EdgeInsets.all(16),
        child: const Text('This conversation has ended.',
            style: TextStyle(color: _muted)),
      );
    }
    return Container(
      decoration: const BoxDecoration(
          color: _card, border: Border(top: BorderSide(color: _rule))),
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 6),
      child: Column(children: [
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: TextField(
              controller: _input,
              focusNode: _focus,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              style: const TextStyle(fontSize: 13.5, color: _text),
              decoration: InputDecoration(
                hintText: 'Type a reply…',
                hintStyle: const TextStyle(color: Color(0xFF8A99AD)),
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: Color(0xFFCDD7E3))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                    borderSide: const BorderSide(color: _blue)),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 38,
            height: 38,
            child: Material(
              color: _blue,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: _sending ? null : _send,
                child: const Icon(Icons.send_rounded, color: _onBlue, size: 18),
              ),
            ),
          ),
        ]),
        const Padding(
          padding: EdgeInsets.only(top: 6, left: 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text('Enter to send · Shift+Enter for a new line',
                style: TextStyle(color: _muted, fontSize: 10.5)),
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _paper,
      child: Column(
        children: [
          _header(),
          Expanded(
            child: ListView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(14, 16, 14, 6),
              children: _groups(),
            ),
          ),
          _composer(),
        ],
      ),
    );
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();
  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (k) {
            final phase = ((_c.value - k * 0.15) % 1.0);
            final up = phase < 0.3 ? (phase / 0.3) : (phase < 0.6 ? (0.6 - phase) / 0.3 : 0.0);
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 6,
              height: 6,
              transform: Matrix4.translationValues(0, -2 * up, 0),
              decoration: BoxDecoration(
                color: Color.lerp(const Color(0xFFC3CEDB), const Color(0xFF8495AA), up),
                shape: BoxShape.circle,
              ),
            );
          }),
        ),
      );
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: SizedBox(
              width: 380,
              height: 540,
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
