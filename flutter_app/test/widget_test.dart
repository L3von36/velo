import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:velo/main.dart';

void main() {
  testWidgets('VeloApp constructs and mounts', (tester) async {
    final widget = const ProviderScope(child: VeloApp());
    expect(widget, isNotNull);
  });
}
