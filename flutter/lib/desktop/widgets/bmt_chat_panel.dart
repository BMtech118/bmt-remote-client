// BMT Remote: the technician's docked side panel, to the right of the remote
// screen instead of floating over it: Chat, Device and Terminal tabs. The
// remote screen shrinks to make room, so nothing is covered. Drag the left edge
// to resize; the width is kept.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/chat_page.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

import 'bmt_device_panel.dart';
import 'bmt_terminal_panel.dart';
import 'bmt_toolbar_style.dart';

const _kWidthOption = 'bmt-chat-panel-width';
const double _kMinWidth = 280;
const double _kMaxWidth = 720;
const double _kDefaultWidth = 360;
const double _kTerminalMinWidth = 460;

class BmtChatPanel extends StatefulWidget {
  final ChatModel chatModel;
  final FFI ffi;
  final String id;
  final String title;

  const BmtChatPanel(
      {Key? key,
      required this.chatModel,
      required this.ffi,
      required this.id,
      required this.title})
      : super(key: key);

  @override
  State<BmtChatPanel> createState() => _BmtChatPanelState();
}

class _BmtChatPanelState extends State<BmtChatPanel> {
  late double _width;

  @override
  void initState() {
    super.initState();
    _width = double.tryParse(bind.getLocalFlutterOption(k: _kWidthOption)) ??
        _kDefaultWidth;
    _width = _width.clamp(_kMinWidth, _kMaxWidth);
  }

  void _saveWidth() =>
      bind.setLocalFlutterOption(k: _kWidthOption, v: _width.toStringAsFixed(0));

  Widget _tab(String tab, String icon, String label) {
    final on = widget.chatModel.bmtDockTab.value == tab;
    return InkWell(
      onTap: () => widget.chatModel.bmtDockTab.value = tab,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(
                  color: on ? BmtTb.blue : Colors.transparent, width: 2)),
        ),
        child: Row(children: [
          BmtTb.icon(icon, on ? BmtTb.blue : BmtTb.ink3, size: 17),
          const SizedBox(width: 7),
          Text(translate(label),
              style: TextStyle(
                  color: on ? BmtTb.ink : BmtTb.ink3,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final tab = widget.chatModel.bmtDockTab.value;
      final width = tab == 'terminal' && _width < _kTerminalMinWidth
          ? _kTerminalMinWidth
          : _width;
      return SizedBox(
        width: width,
        child: Row(
          children: [
            // Resize handle on the panel's left edge.
            MouseRegion(
              cursor: SystemMouseCursors.resizeLeftRight,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onHorizontalDragUpdate: (d) => setState(() => _width =
                    (width - d.delta.dx).clamp(_kMinWidth, _kMaxWidth)),
                onHorizontalDragEnd: (_) => _saveWidth(),
                child: Container(width: 5, color: const Color(0xffe3e6eb)),
              ),
            ),
            Expanded(
              child: Material(
                color: Colors.white,
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.only(left: 8, right: 4),
                      decoration: const BoxDecoration(
                        border: Border(bottom: BorderSide(color: BmtTb.line)),
                      ),
                      child: Row(
                        children: [
                          _tab('chat', 'chat-circle-text', 'Chat'),
                          _tab('device', 'cpu', 'Device'),
                          _tab('terminal', 'terminal-window', 'Terminal'),
                          const Spacer(),
                          IconButton(
                            tooltip: translate('Close'),
                            icon: const Icon(Icons.close,
                                size: 17, color: BmtTb.ink3),
                            onPressed: () =>
                                widget.chatModel.bmtDockOpen.value = false,
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: IndexedStack(
                        index: const ['chat', 'device', 'terminal']
                            .indexOf(tab)
                            .clamp(0, 2),
                        children: [
                          ChatPage(chatModel: widget.chatModel),
                          BmtDevicePanel(
                            ffi: widget.ffi,
                            id: widget.id,
                            active: tab == 'device',
                            onOpenTerminal: () =>
                                widget.chatModel.bmtDockTab.value = 'terminal',
                          ),
                          BmtTerminalPanel(
                              id: widget.id, active: tab == 'terminal'),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    });
  }
}
