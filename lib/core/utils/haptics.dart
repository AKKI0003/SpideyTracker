import 'package:flutter/services.dart';

class Haptics {
  static void tap() => HapticFeedback.selectionClick();
  static void confirm() => HapticFeedback.lightImpact();
  static void success() => HapticFeedback.mediumImpact();
}