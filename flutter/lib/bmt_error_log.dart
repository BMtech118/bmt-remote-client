import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'models/platform_model.dart';

/// BMT Remote: copy uncaught Dart errors into the app log file, so a fault
/// in any window shows up in ~/Library/Logs/BMT-Remote (or the Windows log)
/// without relaunching from a terminal. Default handling still runs.
void installBmtErrorLog() {
  final previous = FlutterError.onError;
  FlutterError.onError = (details) {
    _logDartError('${details.exceptionAsString()}\n${details.stack}');
    previous?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _logDartError('Unhandled: $error\n$stack');
    return false;
  };
}

void _logDartError(String message) {
  try {
    bind.mainLogDartError(message: message);
  } catch (_) {
    // The FFI is not loaded yet in this window; stdout still has it.
  }
}
