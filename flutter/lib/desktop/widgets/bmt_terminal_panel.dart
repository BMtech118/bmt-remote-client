// BMT Remote: the Terminal tab of the docked panel. A live PowerShell or CMD
// on the remote computer, running as SYSTEM in the background, over the same
// channel as the console's terminal. The session is opened with the pass the
// console issued at Connect, so it runs and is audited as that technician.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../../models/platform_model.dart';
import 'bmt_toolbar_style.dart';

class BmtTerminalPanel extends StatefulWidget {
  final String id;
  final bool active;
  const BmtTerminalPanel({Key? key, required this.id, required this.active})
      : super(key: key);

  @override
  State<BmtTerminalPanel> createState() => _BmtTerminalPanelState();
}

class _BmtTerminalPanelState extends State<BmtTerminalPanel> {
  final _terminal = Terminal(maxLines: 10000);
  final _focus = FocusNode();
  WebSocket? _ws;
  String _shell = 'powershell';
  String _state = 'idle'; // idle, connecting, open, closed
  final _decoder = const Utf8Decoder(allowMalformed: true);

  String get _token => bind.mainGetLocalOption(key: 'bmt-term-${widget.id}');

  @override
  void initState() {
    super.initState();
    _terminal.onOutput = (data) {
      if (_state == 'open') _ws?.add(utf8.encode(data));
    };
    _terminal.onResize = (w, h, pw, ph) {
      if (_state == 'open') {
        _ws?.add(jsonEncode({
          'r': [w, h]
        }));
      }
    };
    if (widget.active) _open();
  }

  @override
  void didUpdateWidget(covariant BmtTerminalPanel old) {
    super.didUpdateWidget(old);
    if (widget.active && !old.active) {
      if (_state == 'idle') _open();
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _ws?.close();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    final token = _token;
    if (token.isEmpty) {
      setState(() => _state = 'closed');
      _terminal.write(
          'The terminal opens when you connect from the BMT Remote console.\r\n');
      return;
    }
    await _ws?.close();
    _ws = null;
    setState(() => _state = 'connecting');
    _terminal.write('\x1b[2J\x1b[H');
    final cols = _terminal.viewWidth > 0 ? _terminal.viewWidth : 100;
    final rows = _terminal.viewHeight > 0 ? _terminal.viewHeight : 30;
    try {
      final ws = await WebSocket.connect(
          'wss://remote.bmtech.co.uk/api/app-term/${widget.id}'
          '?t=${Uri.encodeQueryComponent(token)}&shell=$_shell&cols=$cols&rows=$rows');
      if (!mounted) {
        ws.close();
        return;
      }
      _ws = ws;
      ws.listen((data) {
        if (data is List<int>) {
          _terminal.write(_decoder.convert(data));
          return;
        }
        Map<String, dynamic>? msg;
        try {
          msg = jsonDecode(data as String) as Map<String, dynamic>;
        } catch (_) {
          return;
        }
        if (msg['s'] == 'open') {
          setState(() => _state = 'open');
          _ws?.add(jsonEncode({
            'r': [_terminal.viewWidth, _terminal.viewHeight]
          }));
          _focus.requestFocus();
        } else if (msg['e'] != null) {
          _terminal.write('\r\n\x1b[90m${msg['e']}\x1b[0m\r\n');
        }
      }, onDone: () {
        if (!mounted) return;
        if (_state != 'closed') {
          _terminal.write('\r\n\x1b[90mThe terminal closed.\x1b[0m\r\n');
        }
        setState(() => _state = 'closed');
      }, onError: (_) {});
    } catch (_) {
      if (!mounted) return;
      _terminal.write(
          'Could not open the terminal. Check the computer is online and on the latest BMT Remote.\r\n');
      setState(() => _state = 'closed');
    }
  }

  Widget _shellPill(String shell, String label) {
    final on = _shell == shell;
    return InkWell(
      borderRadius: BorderRadius.circular(7),
      onTap: on && _state != 'closed'
          ? null
          : () {
              _shell = shell;
              _open();
            },
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        margin: const EdgeInsets.only(right: 6),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: on ? BmtTb.blueSoft : Colors.white,
          borderRadius: BorderRadius.circular(7),
          border: Border.all(color: on ? const Color(0xffc6d8f6) : BmtTb.line),
        ),
        child: Text(label,
            style: TextStyle(
                color: on ? BmtTb.blue : BmtTb.ink2,
                fontSize: 12,
                fontWeight: FontWeight.w500)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final status = {
          'connecting': 'Connecting…',
          'open': 'Runs as SYSTEM',
          'closed': 'Closed',
        }[_state] ??
        '';
    return Column(children: [
      Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: BmtTb.line))),
        child: Row(children: [
          _shellPill('powershell', 'PowerShell'),
          _shellPill('cmd', 'CMD'),
          if (_state == 'closed')
            Tooltip(
              message: 'Reconnect',
              child: InkWell(
                borderRadius: BorderRadius.circular(7),
                onTap: _open,
                child: Padding(
                  padding: const EdgeInsets.all(5),
                  child: BmtTb.icon('arrows-clockwise', BmtTb.ink2, size: 16),
                ),
              ),
            ),
          const Spacer(),
          if (_state == 'open')
            BmtTb.icon('shield-check', BmtTb.green, size: 14),
          const SizedBox(width: 6),
          Text(status,
              style: const TextStyle(color: BmtTb.ink3, fontSize: 11.5)),
        ]),
      ),
      Expanded(
        child: Container(
          color: const Color(0xff0f1724),
          padding: const EdgeInsets.fromLTRB(10, 8, 4, 4),
          child: TerminalView(
            _terminal,
            focusNode: _focus,
            autofocus: widget.active,
            textStyle: const TerminalStyle(fontSize: 12.5),
            backgroundOpacity: 0,
          ),
        ),
      ),
    ]);
  }
}
