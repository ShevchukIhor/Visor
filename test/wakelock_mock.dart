import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The wakelock channel is a pigeon [BasicMessageChannel]. Its payload is a
/// `ToggleMessage` — a list whose first element is the enable flag — written
/// under the custom type byte 129. This codec decodes just that flag so a
/// test can assert the direction of each toggle, not only its count.
class _ToggleCodec extends StandardMessageCodec {
  const _ToggleCodec();

  @override
  Object? readValueOfType(int type, ReadBuffer buffer) {
    if (type == 129) {
      return (readValue(buffer)! as List<Object?>)[0];
    }
    return super.readValueOfType(type, buffer);
  }
}

/// Installs a mock for the wakelock pigeon channel and returns the log of
/// every toggle the screens request, in order (`true` = enable).
///
/// Without this mock, any test that yields to the real event loop
/// (`tester.runAsync`) while a wakelock-holding screen is mounted fails:
/// the headless engine answers the channel with null, and pigeon turns a
/// null reply into a `PlatformException`. Pure fake-async tests never
/// receive the reply, which is why only `runAsync` tests need this.
List<bool> mockWakelock(WidgetTester tester) {
  final calls = <bool>[];
  tester.binding.defaultBinaryMessenger.setMockMessageHandler(
    'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
    (message) async {
      final payload =
          const _ToggleCodec().decodeMessage(message) as List<Object?>;
      calls.add(payload[0] as bool);
      // An empty reply list is pigeon's "void success".
      return const StandardMessageCodec().encodeMessage(<Object?>[]);
    },
  );
  return calls;
}
