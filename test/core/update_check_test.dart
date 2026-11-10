import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:standwise/core/update_check.dart';

Map<String, Object?> _release(String tag, {bool prerelease = false}) => {
  'tag_name': tag,
  'html_url': 'https://github.com/o/r/releases/tag/$tag',
  'draft': false,
  'prerelease': prerelease,
  'assets': [
    {
      'name': 'Standwise-${tag.substring(1)}-android.apk',
      'browser_download_url': 'https://dl/app.apk',
    },
    {
      'name': 'Standwise-${tag.substring(1)}-windows.zip',
      'browser_download_url': 'https://dl/win.zip',
    },
  ],
};

UpdateChecker _checker(Object? body, {int status = 200}) => UpdateChecker(
  repo: 'o/r',
  httpClient: MockClient((req) async {
    expect(
      req.url.toString(),
      'https://api.github.com/repos/o/r/releases/latest',
    );
    return http.Response(jsonEncode(body), status);
  }),
);

void main() {
  test('compares versions', () {
    expect(isNewerVersion('v0.1.1', '0.1.0'), isTrue);
    expect(isNewerVersion('v0.2.0', '0.1.9'), isTrue);
    expect(isNewerVersion('v1.0', '0.9.9'), isTrue);
    expect(isNewerVersion('v0.1.0', '0.1.0'), isFalse);
    expect(isNewerVersion('v0.1.0', '0.1.1'), isFalse);
    expect(isNewerVersion('v0.1.0+5', '0.1.0'), isFalse);
    expect(isNewerVersion('dev-latest', '0.1.0'), isFalse);
  });

  test('offers the platform download of a newer release', () async {
    final android = await _checker(_release('v0.1.1'))
        .check(currentVersion: '0.1.0', platform: UpdatePlatform.android);
    expect(android?.version, '0.1.1');
    expect(android?.url.toString(), 'https://dl/app.apk');
    final windows = await _checker(_release('v0.1.1'))
        .check(currentVersion: '0.1.0', platform: UpdatePlatform.windows);
    expect(windows?.url.toString(), 'https://dl/win.zip');
  });

  test('nothing when up to date, pre-release, or the request fails', () async {
    expect(
      await _checker(_release('v0.1.0'))
          .check(currentVersion: '0.1.0', platform: UpdatePlatform.android),
      isNull,
    );
    expect(
      await _checker(_release('v0.2.0', prerelease: true))
          .check(currentVersion: '0.1.0', platform: UpdatePlatform.android),
      isNull,
    );
    expect(
      await _checker(
        {'message': 'rate limited'},
        status: 403,
      ).check(currentVersion: '0.1.0', platform: UpdatePlatform.android),
      isNull,
    );
    final offline = UpdateChecker(
      repo: 'o/r',
      httpClient: MockClient((_) => throw http.ClientException('offline')),
    );
    expect(
      await offline.check(
        currentVersion: '0.1.0',
        platform: UpdatePlatform.android,
      ),
      isNull,
    );
  });
}
