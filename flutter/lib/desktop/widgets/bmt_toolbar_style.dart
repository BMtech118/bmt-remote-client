// BMT Remote: the floating capsule look for the technician toolbar.
// The toolbar's behaviour (menus, docking, collapse) stays upstream; this file
// only supplies the palette, the Phosphor icon set and the capsule pieces.
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:get/get.dart';

import '../../common.dart';
import '../../consts.dart';
import '../../models/model.dart';
import '../../models/platform_model.dart';
import 'tabbar_widget.dart';

class BmtTb {
  static const blue = Color(0xff0a53c4);
  static const blueSoft = Color(0xffeaf1fd);
  static const ink = Color(0xff14171c);
  static const ink2 = Color(0xff4a515c);
  static const ink3 = Color(0xff8a919c);
  static const line = Color(0xffe3e6eb);
  static const paper = Color(0xfffdfdfe);
  static const red = Color(0xffd1343f);
  static const redSoft = Color(0xfffbe9ea);
  static const green = Color(0xff1f9d55);
  // Passed as a button's state colour to show it as switched on (a panel open).
  static const active = Color(0xff0a53c5);

  static const double radius = 14;
  static const double buttonSize = 36;
  static const double iconSize = 19;
  static const double buttonRadius = 9;

  static const capsuleShadow = [
    BoxShadow(color: Color(0x140d1a2e), blurRadius: 0, spreadRadius: 1),
    BoxShadow(
        color: Color(0x99050c1e),
        blurRadius: 40,
        offset: Offset(0, 18),
        spreadRadius: -14),
  ];

  static const menuShadow = [
    BoxShadow(color: Color(0x140d1a2e), blurRadius: 0, spreadRadius: 1),
    BoxShadow(
        color: Color(0x590d1a2e),
        blurRadius: 44,
        offset: Offset(0, 22),
        spreadRadius: -14),
  ];

  static const _icons = {
    'assets/actions.svg': 'lightning',
    'assets/actions_mobile.svg': 'dots-three-circle',
    'assets/display.svg': 'sliders-horizontal',
    'assets/display_switcher.svg': 'squares-four',
    'assets/screen.svg': 'monitor',
    'assets/keyboard_mouse.svg': 'keyboard',
    'assets/chat.svg': 'chat-circle-text',
    'assets/message_24dp_5F6368.svg': 'chat-circle-text',
    'assets/voice_call.svg': 'phone',
    'assets/call_wait.svg': 'phone-incoming',
    'assets/rec.svg': 'record',
    'assets/pinned.svg': 'push-pin',
    'assets/unpinned.svg': 'push-pin-slash',
    'assets/close.svg': 'power',
  };

  /// The Phosphor duotone asset for an upstream toolbar icon, or null to keep
  /// the original artwork.
  static String? iconFor(String? asset) {
    if (asset != null && asset.startsWith('assets/bmt/')) return asset;
    final name = _icons[asset];
    return name == null ? null : 'assets/bmt/ph-$name.svg';
  }

  static Widget glyph(String asset, Color color, {double size = iconSize}) =>
      SvgPicture.asset(
        asset,
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      );

  static Widget icon(String name, Color color, {double size = iconSize}) =>
      glyph('assets/bmt/ph-$name.svg', color, size: size);

  /// Upstream passes a "state" colour per button: red for destructive or
  /// recording, blue for normal, grey for switched off.
  static bool isRed(Color c) =>
      c == Colors.redAccent || c == Colors.red || c == red;

  static Color iconColor(Color upstream, bool hover) {
    if (isRed(upstream)) return red;
    return hover || upstream == active ? blue : ink2;
  }

  static Color hoverFill(Color upstream, bool hover) {
    if (upstream == active) return blueSoft;
    if (!hover) return Colors.transparent;
    return isRed(upstream) ? redSoft : blueSoft;
  }

  static MenuStyle menuStyle() => MenuStyle(
        backgroundColor: const MaterialStatePropertyAll(Colors.white),
        surfaceTintColor: const MaterialStatePropertyAll(Colors.white),
        elevation: const MaterialStatePropertyAll(12),
        shadowColor: const MaterialStatePropertyAll(Color(0x590d1a2e)),
        side: const MaterialStatePropertyAll(BorderSide(color: line)),
        shape: MaterialStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
        padding: const MaterialStatePropertyAll(EdgeInsets.all(6)),
      );
}

/// Thin separator between groups of capsule buttons.
class BmtTbDivider extends StatelessWidget {
  final bool horizontal;
  const BmtTbDivider({Key? key, this.horizontal = true}) : super(key: key);

  @override
  Widget build(BuildContext context) => horizontal
      ? Container(
          width: 1,
          height: 22,
          color: BmtTb.line,
          margin: const EdgeInsets.symmetric(horizontal: 5))
      : Container(
          width: 22,
          height: 1,
          color: BmtTb.line,
          margin: const EdgeInsets.symmetric(vertical: 5));
}

/// Which computer this is, at the start of the capsule.
class BmtMachineChip extends StatelessWidget {
  final FFI ffi;
  final bool horizontal;
  const BmtMachineChip({Key? key, required this.ffi, this.horizontal = true})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    final avatar = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
          color: BmtTb.blueSoft, borderRadius: BorderRadius.circular(8)),
      alignment: Alignment.center,
      child: BmtTb.icon('desktop-tower', BmtTb.blue, size: 17),
    );
    if (!horizontal) {
      return Padding(padding: const EdgeInsets.all(4), child: avatar);
    }
    return Obx(() {
      final pi = ffi.ffiModel.pi;
      final ready = ffi.ffiModel.pi.isSet.isTrue;
      final name = ready && pi.hostname.isNotEmpty ? pi.hostname : ffi.id;
      final detail = ready
          ? [pi.username, pi.platform].where((s) => s.isNotEmpty).join(' · ')
          : 'Connecting';
      return Container(
        height: 30,
        padding: const EdgeInsets.only(left: 6, right: 12),
        margin: const EdgeInsets.only(right: 4),
        decoration: const BoxDecoration(
            border: Border(right: BorderSide(color: BmtTb.line))),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          avatar,
          const SizedBox(width: 9),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  style: const TextStyle(
                      color: BmtTb.ink,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      height: 1.15)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: ready ? BmtTb.green : BmtTb.ink3,
                      shape: BoxShape.circle),
                ),
                const SizedBox(width: 5),
                Text(detail,
                    style: const TextStyle(
                        color: BmtTb.ink3, fontSize: 11.5, height: 1.2)),
              ]),
            ],
          ),
        ]),
      );
    });
  }
}

/// The red "End" button that closes the session.
class BmtEndButton extends StatefulWidget {
  final VoidCallback onPressed;
  final bool horizontal;
  const BmtEndButton(
      {Key? key, required this.onPressed, this.horizontal = true})
      : super(key: key);

  @override
  State<BmtEndButton> createState() => _BmtEndButtonState();
}

class _BmtEndButtonState extends State<BmtEndButton> {
  bool hover = false;

  @override
  Widget build(BuildContext context) {
    final bg = hover ? const Color(0xffb82b35) : BmtTb.red;
    return Tooltip(
      message: 'End session',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hover = true),
        onExit: (_) => setState(() => hover = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            height: 34,
            margin: widget.horizontal
                ? const EdgeInsets.only(left: 6, right: 2)
                : const EdgeInsets.only(top: 6, bottom: 2),
            padding: EdgeInsets.symmetric(
                horizontal: widget.horizontal ? 12 : 8),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(9)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              BmtTb.icon('power', Colors.white, size: 16),
              if (widget.horizontal) ...[
                const SizedBox(width: 7),
                const Text('End',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ],
            ]),
          ),
        ),
      ),
    );
  }
}

/// The remote window's tab bar: navy, with the selected tab lifted out of it.
class BmtTabBar {
  static const navy = Color(0xff07172c); // brand pack navy
  static const selected = Color(0xff1b2a43);

  static const theme = TabbarTheme(
      selectedTabIconColor: Color(0xff7fb2ff),
      unSelectedTabIconColor: Color(0xff8a98b0),
      selectedTextColor: Color(0xffeef2f8),
      unSelectedTextColor: Color(0xff8a98b0),
      selectedIconColor: Color(0xffc9d3e3),
      unSelectedIconColor: Color(0xff8a98b0),
      dividerColor: Color(0xff243652),
      hoverColor: Color(0xff16263f),
      closeHoverColor: Color(0xff243652),
      selectedTabBackgroundColor: Colors.transparent);

  /// Wraps the remote window so its tab bar uses the navy theme.
  static Widget wrap(BuildContext context, Widget child) {
    final base = Theme.of(context);
    final others = base.extensions.values.where((e) => e is! TabbarTheme);
    return Theme(
      data: base.copyWith(extensions: [...others, theme]),
      child: child,
    );
  }
}

/// From a Mac, Cmd+C and Cmd+V should copy and paste on a Windows or Linux
/// machine. Turn on the existing "Swap control-command key" option the first
/// time a Mac technician controls that machine; their own choice wins after.
void bmtDefaultMacCommandKeys(FFI ffi) {
  if (!isMacOS) return;
  void apply() {
    final pi = ffi.ffiModel.pi;
    if (pi.platform == kPeerPlatformMacOS) return;
    final flag = 'bmt-swap-default-${ffi.id}';
    if (bind.mainGetLocalOption(key: flag) == 'Y') return;
    bind.mainSetLocalOption(key: flag, value: 'Y');
    if (!bind.sessionGetToggleOptionSync(
        sessionId: ffi.sessionId, arg: 'allow_swap_key')) {
      bind.sessionToggleOption(sessionId: ffi.sessionId, value: 'allow_swap_key');
    }
  }

  if (ffi.ffiModel.pi.isSet.isTrue) {
    apply();
  } else {
    once(ffi.ffiModel.pi.isSet, (bool set) {
      if (set) apply();
    });
  }
}

/// One machine tab in the remote window: icon, name, and the ID kept quiet.
class BmtTabChip extends StatelessWidget {
  final FFI? ffi;
  final String id;
  final bool selected;
  final Widget? trailing;
  const BmtTabChip(
      {Key? key,
      required this.ffi,
      required this.id,
      required this.selected,
      this.trailing})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Obx needs something observable to read; before the session exists there
    // is nothing to watch, so draw it once.
    if (ffi == null) return _chip();
    return Obx(_chip);
  }

  Widget _chip() {
    {
      final alias = bind.mainGetPeerOptionSync(id: id, key: 'alias');
      final host = ffi?.ffiModel.pi.isSet.isTrue == true
          ? ffi!.ffiModel.pi.hostname
          : '';
      final name = alias.isNotEmpty ? alias : (host.isNotEmpty ? host : id);
      return Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: selected
            ? BoxDecoration(
                color: BmtTabBar.selected,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xff2a3c5a)),
              )
            : null,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          BmtTb.icon('desktop-tower',
              selected ? const Color(0xff7fb2ff) : const Color(0xff8a98b0),
              size: 15),
          const SizedBox(width: 8),
          Text(name,
              style: TextStyle(
                  color: selected
                      ? const Color(0xffeef2f8)
                      : const Color(0xff9aa7bd),
                  fontSize: 13,
                  fontWeight: FontWeight.w600)),
          if (name != id) ...[
            const SizedBox(width: 7),
            Text(id,
                style: const TextStyle(
                    color: Color(0xff6f7f99),
                    fontSize: 11.5,
                    fontWeight: FontWeight.w400)),
          ],
          if (trailing != null) trailing!,
        ]),
      );
    }
  }
}
