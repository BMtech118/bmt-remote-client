// BMT Remote: the technician's in-session chat, docked to the right of the
// remote screen instead of floating over it. The remote screen shrinks to make
// room, so nothing is covered. Drag the left edge to resize; the width is kept.
import 'package:flutter/material.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/common/widgets/chat_page.dart';
import 'package:flutter_hbb/models/chat_model.dart';
import 'package:flutter_hbb/models/platform_model.dart';

const _kWidthOption = 'bmt-chat-panel-width';
const double _kMinWidth = 260;
const double _kMaxWidth = 560;
const double _kDefaultWidth = 320;

class BmtChatPanel extends StatefulWidget {
  final ChatModel chatModel;
  final String title;

  const BmtChatPanel({Key? key, required this.chatModel, required this.title})
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _width,
      child: Row(
        children: [
          // Resize handle on the panel's left edge.
          MouseRegion(
            cursor: SystemMouseCursors.resizeLeftRight,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onHorizontalDragUpdate: (d) => setState(() => _width =
                  (_width - d.delta.dx).clamp(_kMinWidth, _kMaxWidth)),
              onHorizontalDragEnd: (_) => _saveWidth(),
              child: Container(width: 5, color: theme.dividerColor),
            ),
          ),
          Expanded(
            child: Material(
              color: theme.colorScheme.surface,
              child: Column(
                children: [
                  Container(
                    height: 44,
                    padding: const EdgeInsets.only(left: 14, right: 4),
                    decoration: BoxDecoration(
                      border: Border(
                          bottom: BorderSide(color: theme.dividerColor)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.chat_bubble_outline,
                            size: 18, color: theme.colorScheme.primary),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(translate('Chat'),
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13)),
                              Text(widget.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 11,
                                      color: theme.hintColor)),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: translate('Close'),
                          icon: const Icon(Icons.close, size: 18),
                          onPressed: () =>
                              widget.chatModel.hideChatWindowOverlay(),
                        ),
                      ],
                    ),
                  ),
                  Expanded(child: ChatPage(chatModel: widget.chatModel)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
