import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

import '../errors.dart';
import 'google_tokens.dart';

/// Google sign-in for Windows: OAuth 2.0 for desktop apps with PKCE and a
/// loopback redirect (RFC 8252). The system browser opens Google's consent
/// page; Google redirects to `http://127.0.0.1:<port>` where a short-lived
/// local [HttpServer] receives the authorization code.
class DesktopGoogleOAuth implements GoogleTokenProvider {
  DesktopGoogleOAuth({
    required this.clientId,
    required this.clientSecret,
    http.Client? httpClient,
    Future<bool> Function(Uri url)? openBrowser,
    this.timeout = const Duration(minutes: 5),
  }) : _http = httpClient ?? http.Client(),
       _openBrowser = openBrowser ?? _defaultOpenBrowser;

  final String clientId;
  final String clientSecret;
  final Duration timeout;
  final http.Client _http;
  final Future<bool> Function(Uri url) _openBrowser;

  static final Uri authEndpoint = Uri.https(
    'accounts.google.com',
    '/o/oauth2/v2/auth',
  );
  static final Uri tokenEndpoint = Uri.https('oauth2.googleapis.com', '/token');

  static Future<bool> _defaultOpenBrowser(Uri url) =>
      launchUrl(url, mode: LaunchMode.externalApplication);

  @override
  Future<GoogleTokens> signIn({
    required BrowserRedirectMessages messages,
  }) async {
    if (clientId.isEmpty) {
      throw const AppException(
        AppErrorCode.googleClientNotConfigured,
        'GOOGLE_DESKTOP_CLIENT_ID is empty',
      );
    }
    final verifier = randomUrlSafe(64);
    final state = randomUrlSafe(24);
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    try {
      final redirectUri = 'http://127.0.0.1:${server.port}';
      final url = buildAuthUrl(
        clientId: clientId,
        redirectUri: redirectUri,
        codeChallenge: pkceChallenge(verifier),
        state: state,
      );
      // Listen before opening the browser so the redirect can't be missed.
      final firstRequest = server.first;
      if (!await _openBrowser(url)) {
        throw const AppException(
          AppErrorCode.signInFailed,
          'Could not open the browser',
        );
      }

      final request = await firstRequest.timeout(
        timeout,
        onTimeout: () => throw const AppException(
          AppErrorCode.signInCancelled,
          'Timed out waiting for the browser redirect',
        ),
      );
      final params = request.uri.queryParameters;
      final ok = params['state'] == state && params['code'] != null;
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write(_page(ok ? messages.success : messages.failure));
      await request.response.close();

      if (params['error'] == 'access_denied') {
        throw const AppException(AppErrorCode.signInCancelled, 'access_denied');
      }
      if (!ok) {
        throw AppException(
          AppErrorCode.signInFailed,
          'Bad redirect: ${params['error'] ?? 'state mismatch or missing code'}',
        );
      }
      return await _exchange(
        code: params['code']!,
        verifier: verifier,
        redirectUri: redirectUri,
      );
    } finally {
      await server.close(force: true);
    }
  }

  Future<GoogleTokens> _exchange({
    required String code,
    required String verifier,
    required String redirectUri,
  }) async {
    final http.Response res;
    try {
      res = await _http.post(
        tokenEndpoint,
        body: {
          'code': code,
          'client_id': clientId,
          if (clientSecret.isNotEmpty) 'client_secret': clientSecret,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
          'code_verifier': verifier,
        },
      );
    } on SocketException catch (e) {
      throw AppException(AppErrorCode.network, e.message);
    }
    if (res.statusCode != 200) {
      throw AppException(
        AppErrorCode.signInFailed,
        'Token exchange ${res.statusCode}: ${res.body}',
      );
    }
    final json = jsonDecode(res.body) as Map<String, dynamic>;
    return GoogleTokens(
      idToken: json['id_token'] as String?,
      accessToken: json['access_token'] as String?,
    );
  }

  @override
  Future<void> signOut() async {
    // Nothing is stored locally; Firebase Auth holds the session.
  }

  static Uri buildAuthUrl({
    required String clientId,
    required String redirectUri,
    required String codeChallenge,
    required String state,
  }) => authEndpoint.replace(
    queryParameters: {
      'client_id': clientId,
      'redirect_uri': redirectUri,
      'response_type': 'code',
      'scope': 'openid email profile',
      'code_challenge': codeChallenge,
      'code_challenge_method': 'S256',
      'state': state,
      'prompt': 'select_account',
    },
  );

  /// S256 code challenge: base64url(sha256(verifier)) without padding.
  static String pkceChallenge(String verifier) =>
      base64UrlEncode(sha256.convert(ascii.encode(verifier)).bytes)
          .replaceAll('=', '');

  static String randomUrlSafe(int length) {
    const chars =
        'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~';
    final rnd = Random.secure();
    return List.generate(
      length,
      (_) => chars[rnd.nextInt(chars.length)],
    ).join();
  }

  static String _page(String message) {
    final safe = const HtmlEscape().convert(message);
    return '<!doctype html><html><head><meta charset="utf-8"><title>$safe</title>'
        '<style>body{font-family:system-ui,sans-serif;display:grid;place-items:center;'
        'height:100vh;margin:0}</style></head><body><p>$safe</p></body></html>';
  }
}
