import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:standwise/core/errors.dart';
import 'package:standwise/data/firebase/callable_client.dart';

void main() {
  CallableClient client(MockClientHandler handler, {String? token = 't0k'}) =>
      CallableClient(
        baseUrl: 'https://europe-west1-p.cloudfunctions.net',
        idToken: () async => token,
        httpClient: MockClient(handler),
      );

  test('posts {data} with the ID token and returns result', () async {
    late http.Request sent;
    final c = client((req) async {
      sent = req;
      return http.Response(
        jsonEncode({
          'result': {'orgId': 'o1'},
        }),
        200,
      );
    });

    final result = await c.call('createOrganization', {'name': 'ACME'});

    expect(result, {'orgId': 'o1'});
    expect(
      sent.url.toString(),
      'https://europe-west1-p.cloudfunctions.net/createOrganization',
    );
    expect(sent.method, 'POST');
    expect(sent.headers['Authorization'], 'Bearer t0k');
    expect(jsonDecode(sent.body), {
      'data': {'name': 'ACME'},
    });
  });

  test('a function error maps by its reason', () async {
    final c = client(
      (_) async => http.Response(
        jsonEncode({
          'error': {
            'status': 'FAILED_PRECONDITION',
            'message': 'expired',
            'details': {'reason': 'invite-expired'},
          },
        }),
        400,
      ),
    );

    await expectLater(
      c.call('acceptInvite', {'code': 'ABCD-EFGH'}),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.inviteExpired,
        ),
      ),
    );
  });

  test('without a reason the status decides', () {
    expect(
      CallableClient.errorFrom({'status': 'INVALID_ARGUMENT'}).code,
      AppErrorCode.invalidInput,
    );
    expect(
      CallableClient.errorFrom({'status': 'UNAUTHENTICATED'}).code,
      AppErrorCode.permissionDenied,
    );
    expect(
      CallableClient.errorFrom({'status': 'INTERNAL'}).code,
      AppErrorCode.unknown,
    );
  });

  test('connection failures and non-JSON replies are reported', () async {
    final offline = client((_) async => throw http.ClientException('no net'));
    await expectLater(
      offline.call('x', {}),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', AppErrorCode.network),
      ),
    );

    final html = client((_) async => http.Response('<html>', 502));
    await expectLater(
      html.call('x', {}),
      throwsA(
        isA<AppException>().having((e) => e.code, 'code', AppErrorCode.unknown),
      ),
    );
  });
}
