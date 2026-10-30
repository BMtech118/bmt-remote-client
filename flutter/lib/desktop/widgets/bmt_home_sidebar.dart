// BMT Remote: the home window's left side. Brand, this computer's ID and
// one-time password, and any setup cards (permissions, install, update).
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

import '../../common.dart';
import '../../models/platform_model.dart';
import '../../models/server_model.dart';
import 'bmt_toolbar_style.dart';

class BmtHomeSidebar extends StatelessWidget {
  final VoidCallback onSettings;
  final Widget cards;
  final Widget? warning;
  const BmtHomeSidebar(
      {Key? key, required this.onSettings, required this.cards, this.warning})
      : super(key: key);

  static const _muted = Color(0xff7d8ba3);

  Widget _iconButton(String icon, String tip, VoidCallback onTap) => Tooltip(
        message: tip,
        child: InkWell(
          borderRadius: BorderRadius.circular(7),
          onTap: onTap,
          child: SizedBox(
              width: 28,
              height: 28,
              child: Center(
                  child: BmtTb.icon(icon, const Color(0xff8a98b0), size: 16))),
        ),
      );

  String _spaced(String id) {
    final digits = id.replaceAll(' ', '');
    final b = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) b.write(' ');
      b.write(digits[i]);
    }
    return b.toString();
  }

  Widget _card(BuildContext context, ServerModel model) {
    final showOneTime = model.approveMode != 'click' &&
        model.verificationMethod != kUsePermanentPassword;
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 14),
      decoration: BoxDecoration(
        color: const Color(0xff16263f),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xff243652)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Text('ID', style: TextStyle(color: _muted, fontSize: 11.5)),
          const Spacer(),
          _iconButton('copy', translate('Copy'), () {
            Clipboard.setData(ClipboardData(text: model.serverId.text));
            showToast(translate('Copied'));
          }),
          _iconButton('gear-six', translate('Settings'), onSettings),
        ]),
        SelectableText(_spaced(model.serverId.text),
            style: const TextStyle(
                color: Color(0xffeef2f8),
                fontSize: 22,
                fontWeight: FontWeight.w500,
                letterSpacing: 0.5)),
        if (showOneTime) ...[
          Container(
              height: 1,
              color: const Color(0xff243652),
              margin: const EdgeInsets.only(top: 12, bottom: 10, right: 6)),
          Row(children: [
            Text(translate('One-time password'),
                style: const TextStyle(color: _muted, fontSize: 11.5)),
            const Spacer(),
            _iconButton('copy', translate('Copy'), () {
              Clipboard.setData(ClipboardData(text: model.serverPasswd.text));
              showToast(translate('Copied'));
            }),
            _iconButton('arrows-clockwise', translate('Refresh Password'),
                () => bind.mainUpdateTemporaryPassword()),
          ]),
          SelectableText(
              model.serverPasswd.text.isEmpty ? '-' : model.serverPasswd.text,
              style: const TextStyle(
                  color: Color(0xffeef2f8),
                  fontSize: 16,
                  letterSpacing: 1.2)),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: gFFI.serverModel,
      child: Container(
        width: 290,
        color: BmtTabBar.navy,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (warning != null) warning!,
                    // The brand pack's logo for dark backgrounds.
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Image.asset('assets/bmt/bmt_remote_logo_dark.png',
                          height: 46, filterQuality: FilterQuality.medium),
                    ),
                    const SizedBox(height: 26),
                    Text(translate('This computer'),
                        style: const TextStyle(
                            color: _muted,
                            fontSize: 11,
                            fontWeight: FontWeight.w500)),
                    const SizedBox(height: 8),
                    Consumer<ServerModel>(
                        builder: (context, model, _) => _card(context, model)),
                    const SizedBox(height: 8),
                    cards,
                  ]),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            // BMT Remote's own version (pubspec), not the RustDesk core's.
            child: FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (_, snap) => Text(
                  snap.hasData
                      ? 'Version ${snap.data!.version} (build ${snap.data!.buildNumber})'
                      : '',
                  style:
                      const TextStyle(color: Color(0xff56647c), fontSize: 11)),
            ),
          ),
        ]),
      ),
    );
  }
}
