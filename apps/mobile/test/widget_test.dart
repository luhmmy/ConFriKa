import 'package:flutter_test/flutter_test.dart';

import 'package:confrika_mobile/core/network/api_client.dart';

void main() {
  test('ApiException exposes its message', () {
    final e = ApiException(404, 'not found');
    expect(e.statusCode, 404);
    expect(e.toString(), 'not found');
  });
}
