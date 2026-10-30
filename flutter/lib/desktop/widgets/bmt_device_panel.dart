// BMT Remote: the Device tab of the docked panel. Who the computer is (from the
// session's peer info) and its live CPU, memory and disk, polled from the
// console with the short-lived token handed over at Connect.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;

import '../../common.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'bmt_toolbar_style.dart';

class BmtDevicePanel extends StatefulWidget {
  final FFI ffi;
  final String id;
  final bool active;
  final VoidCallback onOpenTerminal;
  const BmtDevicePanel(
      {Key? key,
      required this.ffi,
      required this.id,
      required this.active,
      required this.onOpenTerminal})
      : super(key: key);

  @override
  State<BmtDevicePanel> createState() => _BmtDevicePanelState();
}

class _BmtDevicePanelState extends State<BmtDevicePanel> {
  Timer? _timer;
  Map<String, dynamic>? _metrics;
  String _publicIp = '';
  String _status = '';

  String get _token =>
      bind.mainGetLocalOption(key: 'bmt-metrics-${widget.id}');

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant BmtDevicePanel old) {
    super.didUpdateWidget(old);
    if (old.active != widget.active) _sync();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // Poll only while the tab is showing.
  void _sync() {
    _timer?.cancel();
    _timer = null;
    if (!widget.active) return;
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _poll());
  }

  Future<void> _poll() async {
    final token = _token;
    if (token.isEmpty) {
      setState(() => _status =
          'Live figures show when you connect from the BMT Remote console.');
      return;
    }
    try {
      final r = await http
          .get(Uri.parse(
              'https://remote.bmtech.co.uk/api/peer-metrics?t=${Uri.encodeQueryComponent(token)}'))
          .timeout(const Duration(seconds: 8));
      if (!mounted) return;
      if (r.statusCode != 200) {
        setState(() => _status = 'Live figures unavailable (${r.statusCode}).');
        return;
      }
      final d = jsonDecode(r.body);
      setState(() {
        if (d is Map && d['publicIp'] is String) _publicIp = d['publicIp'];
        if (d is Map && d['metrics'] is Map) {
          _metrics = Map<String, dynamic>.from(d['metrics'] as Map);
          _status = '';
        } else {
          _status = 'Waiting for the computer…';
        }
      });
    } catch (_) {
      if (mounted) {
        setState(() => _status = 'Could not reach the BMT Remote service.');
      }
    }
  }

  double _num(dynamic v) => v is num ? v.toDouble() : 0;

  // 429 hours reads as "17 days 21 hours".
  String _uptime(double hours) {
    final h = hours.floor();
    if (h < 1) return '${(hours * 60).round()} minutes';
    final d = h ~/ 24, r = h % 24;
    String unit(int n, String w) => '$n $w${n == 1 ? '' : 's'}';
    if (d == 0) return unit(r, 'hour');
    return r == 0 ? unit(d, 'day') : '${unit(d, 'day')} ${unit(r, 'hour')}';
  }

  Widget _card(Widget child) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: BmtTb.line),
        ),
        child: child,
      );

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          SizedBox(
              width: 92,
              child: Text(k,
                  style: const TextStyle(color: BmtTb.ink3, fontSize: 12.5))),
          Expanded(
              child: Text(v,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: BmtTb.ink, fontSize: 12.5))),
        ]),
      );

  Widget _meter(String label, double pct, String value) {
    final warn = pct >= 85;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(label,
              style: const TextStyle(
                  color: BmtTb.ink, fontSize: 13, fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value, style: const TextStyle(color: BmtTb.ink3, fontSize: 12)),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: (pct / 100).clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: const Color(0xfff4f5f7),
            color: warn ? const Color(0xffc27a12) : BmtTb.blue,
          ),
        ),
      ]),
    );
  }

  Widget _stat(String label, String value) => Expanded(
        child: _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(color: BmtTb.ink3, fontSize: 11.5)),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: const TextStyle(
                    color: BmtTb.ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w500)),
          ),
        ])),
      );

  Widget _action(String icon, String label, VoidCallback onTap) => Expanded(
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Container(
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: BmtTb.line),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              BmtTb.icon(icon, BmtTb.blue, size: 17),
              const SizedBox(width: 7),
              Text(label,
                  style: const TextStyle(
                      color: BmtTb.ink2,
                      fontSize: 13,
                      fontWeight: FontWeight.w500)),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xfffbfbfc),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      child: Obx(() {
        final pi = widget.ffi.ffiModel.pi;
        final name = pi.hostname.isNotEmpty ? pi.hostname : widget.id;
        final display = pi.displays.isNotEmpty
            ? '${pi.displays[0].width} × ${pi.displays[0].height}'
            : '';
        final m = _metrics;
        final ramGb = _num(m?['RamGb']);
        final ramUsed = ramGb - _num(m?['RamFreeGb']);
        final diskGb = _num(m?['DiskGb']);
        final diskUsed = diskGb - _num(m?['DiskFreeGb']);
        return ListView(children: [
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                    color: BmtTb.blueSoft,
                    borderRadius: BorderRadius.circular(10)),
                alignment: Alignment.center,
                child: BmtTb.icon('desktop-tower', BmtTb.blue, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: BmtTb.ink,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  if (pi.username.isNotEmpty)
                    Text('Signed in as ${pi.username}',
                        style:
                            const TextStyle(color: BmtTb.ink3, fontSize: 12)),
                ]),
              ),
            ]),
            const SizedBox(height: 6),
            if (pi.platform.isNotEmpty) _kv('System', pi.platform),
            if (display.isNotEmpty) _kv('Display', display),
            if (_metrics?['LocalIp'] is String &&
                (_metrics!['LocalIp'] as String).isNotEmpty)
              _kv('Local IP', _metrics!['LocalIp']),
            if (_publicIp.isNotEmpty) _kv('Public IP', _publicIp),
            if (pi.version.isNotEmpty) _kv('Agent', 'BMT Remote ${pi.version}'),
          ])),
          const SizedBox(height: 14),
          _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: const [
              Text('Live',
                  style: TextStyle(
                      color: BmtTb.ink3,
                      fontSize: 11,
                      fontWeight: FontWeight.w500)),
              Spacer(),
              Text('Updates every few seconds',
                  style: TextStyle(color: BmtTb.ink3, fontSize: 11)),
            ]),
            const SizedBox(height: 12),
            if (m == null)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(_status.isEmpty ? 'Loading…' : _status,
                    style: const TextStyle(color: BmtTb.ink2, fontSize: 12.5)),
              )
            else ...[
              _meter('CPU', _num(m['CpuLoad']), '${_num(m['CpuLoad']).round()}%'),
              if (ramGb > 0)
                _meter('Memory', ramUsed / ramGb * 100,
                    '${ramUsed.toStringAsFixed(1)} of ${ramGb.toStringAsFixed(0)} GB'),
              if (diskGb > 0)
                _meter('Disk C:', diskUsed / diskGb * 100,
                    '${_num(m['DiskFreeGb']).toStringAsFixed(0)} GB free'),
            ],
          ])),
          if (m != null) ...[
            const SizedBox(height: 14),
            Row(children: [
              _stat('Processes', '${_num(m['Procs']).round()}'),
              const SizedBox(width: 10),
              _stat('Up for', _uptime(_num(m['UptimeHours']))),
            ]),
          ],
          const SizedBox(height: 14),
          Row(children: [
            _action('terminal-window', 'Terminal', widget.onOpenTerminal),
            const SizedBox(width: 8),
            _action('folder-simple-dashed', 'Files',
                () => connect(context, widget.id,
                    isFileTransfer: true,
                    // Reuse this session's sign-in, so no password prompt.
                    connToken: bind.sessionGetConnToken(
                        sessionId: widget.ffi.sessionId))),
          ]),
        ]);
      }),
    );
  }
}
