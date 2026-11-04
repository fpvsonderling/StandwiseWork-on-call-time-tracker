import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:standwise/core/auth/desktop_google_oauth.dart';
import 'package:standwise/core/auth/google_tokens.dart';
import 'package:standwise/core/errors.dart';

const _messages = BrowserRedirectMessages(success: 'ok', failure: 'fail');

late Future<String> browserPage;

Future<String> _get(Uri url) async {
  final hc = HttpClient();
  try {
    final res = await (await hc.getUrl(url)).close();
    return await res.transform(utf8.decoder).join();
  } finally {
    hc.close();
  }
}

void main() {
  test('PKCE S256 challenge matches an independent implementation', () {
    // Python: base64.urlsafe_b64encode(sha256(v).digest()).rstrip('=')
    expect(
      DesktopGoogleOAuth.pkceChallenge(
        'dBjftJeZ4CVP-mJ92ZzD8a4F-gptbXxbwhT8VBOdSm2Nm1q',
      ),
      'On4o2vMnHGc1yZG7_qZOnmEjgvdHUE8wpxw1e46_SBA',
    );
  });

  test('random verifier uses only unreserved characters', () {
    final v = DesktopGoogleOAuth.randomUrlSafe(64);
    expect(v.length, 64);
    expect(RegExp(r'^[A-Za-z0-9\-._~]+$').hasMatch(v), isTrue);
  });

  test('auth URL carries PKCE, state and loopback redirect', () {
    final url = DesktopGoogleOAuth.buildAuthUrl(
      clientId: 'cid',
      redirectUri: 'http://127.0.0.1:1234',
      codeChallenge: 'chal',
      state: 'st',
    );
    expect(url.host, 'accounts.google.com');
    expect(url.queryParameters['code_challenge_method'], 'S256');
    expect(url.queryParameters['redirect_uri'], 'http://127.0.0.1:1234');
    expect(url.queryParameters['scope'], 'openid email profile');
  });

  test('full loopback flow exchanges the code for tokens', () async {
    late Map<String, String> tokenRequest;
    final client = MockClient((req) async {
      tokenRequest = Uri.splitQueryString(req.body);
      return http.Response(
        jsonEncode({'id_token': 'ID', 'access_token': 'AT'}),
        200,
      );
    });
    final oauth = DesktopGoogleOAuth(
      clientId: 'cid',
      clientSecret: 'secret',
      httpClient: client,
      openBrowser: (url) async {
        // Simulate Google redirecting the browser back to the loopback server.
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!)
            .replace(
              queryParameters: {
                'code': 'CODE',
                'state': url.queryParameters['state'],
              },
            );
        // Like a real browser: the redirect happens after launch returns.
        browserPage = _get(redirect);
        return true;
      },
    );
    final tokens = await oauth.signIn(messages: _messages);
    expect(await browserPage, contains('ok'));
    expect(tokens.idToken, 'ID');
    expect(tokens.accessToken, 'AT');
    expect(tokenRequest['code'], 'CODE');
    expect(tokenRequest['grant_type'], 'authorization_code');
    expect(tokenRequest['code_verifier'], isNotEmpty);
    expect(tokenRequest['redirect_uri'], startsWith('http://127.0.0.1:'));
  });

  test('state mismatch fails', () async {
    final oauth = DesktopGoogleOAuth(
      clientId: 'cid',
      clientSecret: '',
      httpClient: MockClient((_) async => http.Response('{}', 200)),
      openBrowser: (url) async {
        final redirect = Uri.parse(url.queryParameters['redirect_uri']!)
            .replace(queryParameters: {'code': 'CODE', 'state': 'forged'});
        browserPage = _get(redirect);
        return true;
      },
    );
    await expectLater(
      oauth.signIn(messages: _messages),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.signInFailed,
        ),
      ),
    );
  });

  test('missing client ID reports a configuration error', () async {
    final oauth = DesktopGoogleOAuth(clientId: '', clientSecret: '');
    await expectLater(
      oauth.signIn(messages: _messages),
      throwsA(
        isA<AppException>().having(
          (e) => e.code,
          'code',
          AppErrorCode.googleClientNotConfigured,
        ),
      ),
    );
  });
}
