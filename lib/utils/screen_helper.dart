import 'package:auto_orientation/auto_orientation.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 屏幕方向
enum ScreenDirction {
  /// 横屏
  x,

  /// 竖屏
  y
}

/// 切换屏幕方向
/// [action] 操作的方向
/// [beforeTime] 在执行该操作时, 猜测若有其他异步操作, 会卡死 `Flutter Engine`
execScreenDirction(
  ScreenDirction action, [
  beforeTime = const Duration(seconds: 1),
]) {
  /// 为避免卡死, 在开发模式下不执行操作
  if (kReleaseMode) {
    Future.delayed(beforeTime, () {
      switch (action) {
        case ScreenDirction.x:
          AutoOrientation.landscapeAutoMode();
          break;
        case ScreenDirction.y:
          AutoOrientation.portraitAutoMode();
          break;
        default:
      }
      SystemUiOverlayStyle systemUiOverlayStyle = SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
      );
      SystemChrome.setSystemUIOverlayStyle(systemUiOverlayStyle);
    });
  }
}
