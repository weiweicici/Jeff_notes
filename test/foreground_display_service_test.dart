import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jeff_notes/services/foreground_display_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('foreground display mode never overrides screen brightness', () async {
    const channel = MethodChannel('com.zhenfeng.jeffnotes/wakelock');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          return true;
        });

    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    await ForegroundDisplayService.setActive(true);
    await ForegroundDisplayService.setActive(false);

    expect(calls, hasLength(2));
    expect(calls[0].method, 'setForegroundDisplayMode');
    expect(calls[0].arguments, <String, Object>{'enable': true});
    expect(calls[1].arguments, <String, Object>{'enable': false});

    final nativeSource = File(
      'ios/Runner/AppDelegate.swift',
    ).readAsStringSync();
    expect(nativeSource, isNot(contains('UIScreen.main.brightness')));
    expect(nativeSource, isNot(contains('0.05')));
  });
}
