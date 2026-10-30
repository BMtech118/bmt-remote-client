// BMT Remote: what the customer sees while a technician is connected. Instead
// of the connection window in the top right, a small bubble sits on the right
// edge of the screen: who is connected, chat and end. Click it to open a panel
// with what the technician can do (each a switch the customer controls) and
// the chat. Used only once every connection is accepted; anything still
// waiting for Accept shows the normal window.
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:window_manager/window_manager.dart';

import '../../common.dart';
import '../../common/widgets/chat_page.dart';
import '../../consts.dart';
import '../../models/chat_model.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'bmt_toolbar_style.dart';

class BmtCmBubble {
  static final showing = false.obs;
  static final expanded = true.obs;
  static final tab = 'session'.obs;
  static final Map<int, DateTime> _since = {};

  static const _collapsed = Size(272, 56);
  static const _panelWidth = 380.0;

  static bool eligible(List<Client> clients) =>
      (isWindows || isMacOS) &&
      clients.isNotEmpty &&
      clients.every((c) =>
          c.authorized && !c.disconnected && c.type_() == ClientType.remote);

  static DateTime since(Client c) =>
      _since.putIfAbsent(c.id, () => DateTime.now());

  /// Puts the window where the bubble or panel belongs. Called whenever the
  /// window is shown again, so the upstream size and position don't win.
  static Future<void> reapply() async {
    if (showing.value) await _applySettled();
  }

  static Future<void> _apply() async {
    // Always pinned to the middle of the right-hand edge, open or collapsed
    // (Mace, 30 Oct 2026). The connection window is briefly minimised
    // whenever it is shown; a resize on its own leaves it off-screen.
    if (await windowManager.isMinimized()) await windowManager.restore();
    final size = expanded.value
        ? Size(_panelWidth, tab.value == 'chat' ? 600 : 560)
        : _collapsed;
    await windowManager.setSizeAlignment(size, Alignment.centerRight);
    if (!await windowManager.isVisible()) await windowManager.show();
  }

  /// Applies the position now and again shortly after, because the upstream
  /// window code can still be moving the window when it is first shown.
  static Future<void> _applySettled() async {
    await _apply();
    await Future.delayed(const Duration(milliseconds: 400));
    if (showing.value) await _apply();
  }

  static void open(String which) {
    tab.value = which;
    expanded.value = true;
  }

  /// The upstream "open the chat side page" request, while the bubble is up.
  static void openChat() => open('chat');
}

class BmtCmBubbleView extends StatefulWidget {
  final List<Client> clients;
  const BmtCmBubbleView({Key? key, required this.clients}) : super(key: key);

  @override
  State<BmtCmBubbleView> createState() => _BmtCmBubbleViewState();
}

class _BmtCmBubbleViewState extends State<BmtCmBubbleView> {
  final List<Worker> _workers = [];

  Client get _client => widget.clients.first;

  @override
  void initState() {
    super.initState();
    BmtCmBubble.showing.value = true;
    BmtCmBubble.tab.value = 'session';
    // Start as the small tab on the screen edge; the customer opens it.
    BmtCmBubble.expanded.value = false;
    _workers
        .add(ever(BmtCmBubble.expanded, (_) => BmtCmBubble._applySettled()));
    _workers.add(ever(BmtCmBubble.tab, (t) {
      if (t == 'chat') _focusChat();
      BmtCmBubble._apply();
    }));
    WidgetsBinding.instance
        .addPostFrameCallback((_) => BmtCmBubble._applySettled());
  }

  @override
  void dispose() {
    for (final w in _workers) {
      w.dispose();
    }
    BmtCmBubble.showing.value = false;
    // Hand the window back to the normal connection window.
    windowManager.setSizeAlignment(
        kConnectionManagerWindowSizeClosedChat, Alignment.topRight);
    super.dispose();
  }

  void _focusChat() {
    final c = _client;
    gFFI.chatModel.changeCurrentKey(MessageKey(c.peerId, c.id));
    c.unreadChatMessageCount.value = 0;
  }

  void _endSession() {
    for (final c in widget.clients) {
      bind.cmCloseConnection(connId: c.id);
    }
  }

  String get _name => _client.name.isNotEmpty ? _client.name : 'Support';

  Widget _avatar(double size, Color ring) => Stack(children: [
        Container(
          width: size,
          height: size,
          decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xff2a6fe0), BmtTb.blue])),
          alignment: Alignment.center,
          child: Text(_name.characters.first.toUpperCase(),
              style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: size * 0.4)),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: Container(
            width: size * 0.3,
            height: size * 0.3,
            decoration: BoxDecoration(
                color: const Color(0xff3ccf7e),
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: 2)),
          ),
        ),
      ]);

  Widget _iconButton(String icon, String tip, VoidCallback onTap,
          {Widget? badge}) =>
      Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: onTap,
          child: SizedBox(
            width: 32,
            height: 32,
            child: Stack(alignment: Alignment.center, children: [
              BmtTb.icon(icon, const Color(0xffb9c5d8), size: 18),
              if (badge != null) Positioned(top: 5, right: 5, child: badge),
            ]),
          ),
        ),
      );

  Widget _collapsedView() {
    return Material(
      color: BmtTabBar.navy,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        child: Row(children: [
          InkWell(
            onTap: () => BmtCmBubble.open('session'),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
              child:
                  BmtTb.icon('caret-left', const Color(0xff7d8ba3), size: 14),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => BmtCmBubble.open('session'),
              child: Row(children: [
                _avatar(32, BmtTabBar.navy),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Color(0xffeef2f8),
                                fontWeight: FontWeight.w500,
                                fontSize: 13)),
                        const Text('BM Technologies',
                            style: TextStyle(
                                color: Color(0xff7d8ba3), fontSize: 11.5)),
                      ]),
                ),
              ]),
            ),
          ),
          Container(width: 1, height: 24, color: const Color(0xff243652)),
          const SizedBox(width: 4),
          Obx(() => _iconButton('chat-circle-text', translate('Chat'),
              () => BmtCmBubble.open('chat'),
              badge: _client.unreadChatMessageCount.value > 0
                  ? Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                          color: Color(0xff4d8dff), shape: BoxShape.circle))
                  : null)),
          _iconButton('x', translate('End session'), _endSession),
          const SizedBox(width: 6),
        ]),
      ),
    );
  }

  Widget _tab(String which, String icon, String label, {int unread = 0}) {
    final on = BmtCmBubble.tab.value == which;
    return InkWell(
      onTap: () => BmtCmBubble.tab.value = which,
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(
                    color: on ? BmtTb.blue : Colors.transparent, width: 2))),
        child: Row(children: [
          BmtTb.icon(icon, on ? BmtTb.blue : BmtTb.ink3, size: 17),
          const SizedBox(width: 7),
          Text(translate(label),
              style: TextStyle(
                  color: on ? BmtTb.ink : BmtTb.ink3,
                  fontWeight: FontWeight.w500,
                  fontSize: 13)),
          if (unread > 0) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              height: 16,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: BmtTb.blue, borderRadius: BorderRadius.circular(8)),
              child: Text('$unread',
                  style: const TextStyle(color: Colors.white, fontSize: 10.5)),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _perm(String icon, String label, bool? value, String name) {
    final canModify =
        bind.mainGetBuildinOption(key: kOptionEnablePermChangeInAcceptWindow) !=
            'N';
    return SizedBox(
      height: 40,
      child: Row(children: [
        SizedBox(width: 22, child: BmtTb.icon(icon, BmtTb.blue, size: 18)),
        const SizedBox(width: 10),
        Expanded(
            child: Text(translate(label),
                style: const TextStyle(color: BmtTb.ink, fontSize: 13))),
        if (value != null)
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: value,
              activeColor: Colors.white,
              activeTrackColor: BmtTb.blue,
              inactiveThumbColor: Colors.white,
              inactiveTrackColor: const Color(0xffcfd4dc),
              onChanged: canModify
                  ? (v) {
                      for (final c in widget.clients) {
                        bind.cmSwitchPermission(
                            connId: c.id, name: name, enabled: v);
                        switch (name) {
                          case 'keyboard':
                            c.keyboard = v;
                            break;
                          case 'clipboard':
                            c.clipboard = v;
                            break;
                          case 'file':
                            c.file = v;
                            break;
                          case 'audio':
                            c.audio = v;
                            break;
                          case 'restart':
                            c.restart = v;
                            break;
                        }
                      }
                      setState(() {});
                    }
                  : null,
            ),
          ),
      ]),
    );
  }

  Widget _sessionTab() {
    final c = _client;
    return ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        children: [
          Text('$_name can',
              style: const TextStyle(
                  color: BmtTb.ink3,
                  fontSize: 11,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 4),
          _perm('eye', 'See your screen', null, ''),
          _perm('mouse', 'Use your mouse and keyboard', c.keyboard, 'keyboard'),
          _perm(
              'clipboard-text', 'Use your clipboard', c.clipboard, 'clipboard'),
          _perm(
              'folder-simple-dashed', 'Send and receive files', c.file, 'file'),
          _perm('speaker-high', "Hear your computer's sound", c.audio, 'audio'),
          _perm('arrows-clockwise', 'Restart this computer', c.restart,
              'restart'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xfff4f5f7),
                borderRadius: BorderRadius.circular(10)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              BmtTb.icon('info', BmtTb.blue, size: 16),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                    'You can end the session at any time. $_name will be disconnected straight away.',
                    style: const TextStyle(
                        color: BmtTb.ink2, fontSize: 12, height: 1.45)),
              ),
            ]),
          ),
        ]);
  }

  Widget _footerButton(String icon, String label, VoidCallback onTap,
      {bool danger = false}) {
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          height: 38,
          decoration: BoxDecoration(
            color: danger ? BmtTb.red : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: danger ? null : Border.all(color: BmtTb.line),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            BmtTb.icon(icon, danger ? Colors.white : BmtTb.blue, size: 16),
            const SizedBox(width: 7),
            Text(translate(label),
                style: TextStyle(
                    color: danger ? Colors.white : BmtTb.ink2,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      ),
    );
  }

  Widget _expandedView() {
    final t = BmtCmBubble.since(_client);
    final hhmm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Material(
      color: Colors.white,
      child: Column(children: [
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          child: Container(
            color: BmtTabBar.navy,
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
            child: Row(children: [
              _avatar(40, BmtTabBar.navy),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('$_name is connected',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: Color(0xffeef2f8),
                              fontWeight: FontWeight.w600,
                              fontSize: 14.5)),
                      const SizedBox(height: 2),
                      Text('BM Technologies support · since $hhmm',
                          style: const TextStyle(
                              color: Color(0xff8a98b0), fontSize: 12)),
                    ]),
              ),
              Tooltip(
                message: translate('Minimize'),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => BmtCmBubble.expanded.value = false,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: BmtTb.icon('caret-down', const Color(0xff8a98b0),
                        size: 16),
                  ),
                ),
              ),
            ]),
          ),
        ),
        Container(
          padding: const EdgeInsets.only(left: 8),
          decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: BmtTb.line))),
          child: Obx(() => Row(children: [
                _tab('session', 'shield-check', 'Session'),
                _tab('chat', 'chat-circle-text', 'Chat',
                    unread: BmtCmBubble.tab.value == 'chat'
                        ? 0
                        : _client.unreadChatMessageCount.value),
              ])),
        ),
        Expanded(
          child: Obx(() => BmtCmBubble.tab.value == 'chat'
              ? ChatPage(type: ChatPageType.desktopCM)
              : _sessionTab()),
        ),
        Obx(() => BmtCmBubble.tab.value == 'chat'
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(children: [
                  _footerButton('chat-circle-text', 'Chat',
                      () => BmtCmBubble.open('chat')),
                  const SizedBox(width: 8),
                  _footerButton('power', 'End session', _endSession,
                      danger: true),
                ]),
              )),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Obx(
        () => BmtCmBubble.expanded.value ? _expandedView() : _collapsedView());
  }
}
