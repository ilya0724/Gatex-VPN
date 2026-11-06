import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/core/vpn_core.dart';
import 'package:gatex/state/app_state.dart';
import 'package:gatex/state/settings.dart';
import 'package:gatex/state/updates.dart';
import 'package:gatex/subscription/subscription.dart';
import 'package:gatex/ui/home_screen.dart';
import 'package:gatex/ui/theme.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _asset(String name, {int size = 10, String? digest}) => {
  'name': name,
  'size': size,
  'browser_download_url':
      'https://github.com/ilya0724/Gatex-VPN/releases/download/v1.4.0/$name',
  'digest': ?digest,
};

Map<String, dynamic> _release({String tag = 'v1.4.0'}) => {
  'tag_name': tag,
  'body': 'Что нового',
  'assets': [
    _asset('GateX-arm64.apk', size: 111, digest: 'sha256:${'a' * 64}'),
    _asset('GateX-armv7.apk', size: 222),
    _asset('GateX.apk', size: 333, digest: 'sha256:${'b' * 64}'),
    _asset('GateX-universal.apk'),
    _asset('GateX-Setup.exe', size: 444, digest: 'sha256:${'c' * 64}'),
    _asset('gatex_1.4.0_amd64.deb', size: 555, digest: 'sha256:${'d' * 64}'),
    _asset('GateX-1.4.0-linux-x64.tar.gz'),
  ],
};

class _FakeCore extends Fake implements VpnCore {
  @override
  Future<String> coreVersion() async => '25.0';
}

void main() {
  group('parseGithubRelease', () {
    test('android arm64 takes the arm64 apk, strips v, reads digest/size', () {
      final u = parseGithubRelease(
        _release(),
        '1.3.0',
        platform: 'android',
        abi: 'arm64-v8a',
      )!;
      expect(u.version, '1.4.0');
      expect(u.fileName, 'GateX-arm64.apk');
      expect(
        u.url,
        'https://github.com/ilya0724/Gatex-VPN/releases/download/v1.4.0/GateX-arm64.apk',
      );
      expect(u.sha256, 'a' * 64);
      expect(u.size, 111);
      expect(u.notes, 'Что нового');
    });
    test('android other abi takes GateX.apk', () {
      for (final abi in ['armeabi-v7a', 'x86_64', null]) {
        final u = parseGithubRelease(
          _release(),
          '1.3.0',
          platform: 'android',
          abi: abi,
        )!;
        expect(u.fileName, 'GateX.apk');
      }
    });
    test('windows takes the setup exe', () {
      final u = parseGithubRelease(_release(), '1.3.0', platform: 'windows')!;
      expect(u.fileName, 'GateX-Setup.exe');
      expect(u.sha256, 'c' * 64);
    });
    test('linux takes the versioned amd64 deb', () {
      final u = parseGithubRelease(_release(), '1.3.0', platform: 'linux')!;
      expect(u.fileName, 'gatex_1.4.0_amd64.deb');
      expect(u.size, 555);
    });
    test('null when not newer or asset missing', () {
      expect(
        parseGithubRelease(_release(), '1.4.0', platform: 'windows'),
        isNull,
      );
      expect(
        parseGithubRelease(_release(), '1.10.0', platform: 'windows'),
        isNull,
      );
      final r = _release()..['assets'] = <Object>[];
      expect(parseGithubRelease(r, '1.3.0', platform: 'windows'), isNull);
    });
  });

  group('checkForUpdate', () {
    test('uses GitHub with the right headers', () async {
      late http.Request seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response.bytes(utf8.encode(jsonEncode(_release())), 200);
      });
      final u = await checkForUpdate(
        '1.3.0',
        client: client,
        platform: 'windows',
      );
      expect(u!.version, '1.4.0');
      expect(seen.url.host, 'api.github.com');
      expect(seen.headers['Accept'], 'application/vnd.github+json');
      expect(seen.headers['User-Agent'], 'GateX/1.3.0');
    });
    Future<AppUpdate?> viaManifest(Map<String, dynamic> windows) {
      final client = MockClient((req) async {
        if (req.url.host == 'api.github.com') return http.Response('x', 403);
        return http.Response(
          jsonEncode({'version': '1.5.0', 'notes': 'n', 'windows': windows}),
          200,
        );
      });
      return checkForUpdate('1.3.0', client: client, platform: 'windows');
    }

    const good =
        'https://github.com/ilya0724/Gatex-VPN/releases/download/v1.5.0/GateX-Setup.exe';
    final sha = 'e' * 64;
    test('manifest with a trusted url and sha256 is accepted', () async {
      final u = await viaManifest({'url': good, 'sha256': sha});
      expect(u!.version, '1.5.0');
      expect(u.fileName, 'GateX-Setup.exe');
      expect(u.manual, isFalse);
    });
    test('manifest without sha256 or with a foreign url is manual', () async {
      for (final w in [
        {'url': good},
        {'url': 'https://example.test/GateX-Setup.exe', 'sha256': sha},
        {'url': good.replaceFirst('https', 'http'), 'sha256': sha},
        {
          'url': good.replaceFirst('GateX-Setup.exe', 'evil.exe'),
          'sha256': sha,
        },
        {
          'url': good.replaceFirst('GateX-Setup.exe', '..%2F..%2Fx.exe'),
          'sha256': sha,
        },
        {
          'url': good.replaceFirst('GateX-Setup.exe', '..%5Cx.exe'),
          'sha256': sha,
        },
      ]) {
        final u = await viaManifest(w);
        expect(u!.manual, isTrue, reason: '$w');
        expect(u.url, releasePage);
      }
    });
    test('github release without a digest is manual', () {
      final r = _release();
      (r['assets'] as List).removeWhere((a) => a['name'] == 'GateX-Setup.exe');
      (r['assets'] as List).add(_asset('GateX-Setup.exe'));
      final u = parseGithubRelease(r, '1.3.0', platform: 'windows')!;
      expect(u.manual, isTrue);
      expect(u.url, releasePage);
    });
    test('github release with a foreign download url is manual', () {
      final r = _release();
      for (final a in r['assets'] as List) {
        a['browser_download_url'] = 'https://evil.test/${a['name']}';
      }
      expect(
        parseGithubRelease(r, '1.3.0', platform: 'windows')!.manual,
        isTrue,
      );
    });
  });

  group('downloadUpdate', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('gatex-upd'));
    tearDown(() => dir.deleteSync(recursive: true));

    final body = utf8.encode('hello update body');
    AppUpdate upd({String? sha, int? size}) => AppUpdate(
      version: '1.4.0',
      url: 'https://example.test/dl/GateX-Setup.exe',
      notes: '',
      sha256: sha,
      size: size ?? body.length,
      fileName: 'GateX-Setup.exe',
    );
    MockClient serve() => MockClient.streaming((req, _) async {
      final chunks = [body.sublist(0, 5), body.sublist(5)];
      return http.StreamedResponse(
        Stream.fromIterable(chunks),
        200,
        contentLength: body.length,
      );
    });

    test('progress reaches 1.0 and file is renamed', () async {
      final progress = await downloadUpdate(
        upd(sha: sha256.convert(body).toString()),
        dir.path,
        client: serve(),
      ).toList();
      expect(progress.last, 1.0);
      expect(
        File('${dir.path}/updates/GateX-Setup.exe').readAsBytesSync(),
        body,
      );
      expect(
        File('${dir.path}/updates/GateX-Setup.exe.part').existsSync(),
        isFalse,
      );
    });

    test('wrong sha256 throws and leaves no file', () async {
      await expectLater(
        downloadUpdate(upd(sha: 'deadbeef'), dir.path, client: serve()).drain(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            'Файл повреждён, попробуйте ещё раз',
          ),
        ),
      );
      final left = Directory('${dir.path}/updates').listSync();
      expect(left, isEmpty);
    });

    test('unsafe file name or missing sha256 is refused', () async {
      for (final name in ['../x.exe', r'..\x.exe', 'a/b.exe']) {
        final bad = AppUpdate(
          version: '1.4.0',
          url: 'https://example.test/x',
          notes: '',
          sha256: 'e' * 64,
          fileName: name,
        );
        await expectLater(
          downloadUpdate(bad, dir.path, client: serve()).drain(),
          throwsA(isA<UpdateException>()),
        );
      }
      await expectLater(
        downloadUpdate(upd(), dir.path, client: serve()).drain(),
        throwsA(isA<UpdateException>()),
      );
    });

    test('a stalled body ends with a readable error', () async {
      final ctl = StreamController<List<int>>();
      ctl.add(body.sublist(0, 5));
      final client = MockClient.streaming(
        (req, _) async => http.StreamedResponse(ctl.stream, 200),
      );
      await expectLater(
        downloadUpdate(
          upd(sha: sha256.convert(body).toString()),
          dir.path,
          client: client,
          idle: const Duration(milliseconds: 50),
        ).drain(),
        throwsA(
          isA<UpdateException>().having(
            (e) => e.message,
            'message',
            'Загрузка прервалась, попробуйте ещё раз',
          ),
        ),
      );
      expect(Directory('${dir.path}/updates').listSync(), isEmpty);
    });

    test('a folder that cannot be created is an UpdateException', () async {
      final file = File('${dir.path}/blocker')..writeAsStringSync('x');
      await expectLater(
        downloadUpdate(
          upd(sha: sha256.convert(body).toString()),
          file.path,
          client: serve(),
        ).drain(),
        throwsA(isA<UpdateException>()),
      );
    });

    test('existing verified file completes without a request', () async {
      Directory('${dir.path}/updates').createSync();
      File('${dir.path}/updates/GateX-Setup.exe').writeAsBytesSync(body);
      final client = MockClient((_) async => throw StateError('no request'));
      final progress = await downloadUpdate(
        upd(sha: sha256.convert(body).toString()),
        dir.path,
        client: client,
      ).toList();
      expect(progress, [1.0]);
    });
  });

  group('banner', () {
    Future<AppState> state(UpdatePhase phase) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final s = AppState(core: _FakeCore());
      s.settings = Settings(prefs);
      s.subscription = Subscription(
        url: 'https://example.test/sub',
        servers: const [],
        fetchedAt: DateTime.now(),
        title: 'GateX VPN',
        expire: DateTime.now().add(const Duration(days: 352)),
        announce: 'Тариф: Стандарт (LTE)',
      );
      s.update = AppUpdate(
        version: '1.4.0',
        url: 'https://example.test/x',
        notes: '',
        fileName: 'GateX-Setup.exe',
        sha256: 'e' * 64,
      );
      s.updatePhase = phase;
      s.updateProgress = 0.42;
      s.updateError = 'Не удалось скачать обновление';
      return s;
    }

    const texts = {
      UpdatePhase.available: ['Доступна версия 1.4.0', 'Обновить сейчас'],
      UpdatePhase.downloading: ['Загрузка… 42%'],
      UpdatePhase.ready: ['Версия 1.4.0 загружена', 'Установить'],
      UpdatePhase.installing: ['Устанавливаем…'],
      UpdatePhase.failed: ['Не удалось скачать обновление', 'Повторить'],
    };
    for (final entry in texts.entries) {
      for (final size in const [Size(360, 640), Size(720, 520)]) {
        testWidgets('${entry.key.name} ${size.width.toInt()}', (t) async {
          t.view.physicalSize = size;
          t.view.devicePixelRatio = 1;
          addTearDown(t.view.reset);
          await t.pumpWidget(
            MaterialApp(
              theme: buildTheme(),
              home: HomeScreen(state: await state(entry.key)),
            ),
          );
          await t.pump(const Duration(seconds: 6));
          expect(t.takeException(), isNull);
          for (final s in entry.value) {
            expect(find.text(s), findsOneWidget);
          }
          for (final s in t.stateList<ScrollableState>(
            find.byType(Scrollable),
          )) {
            expect(s.position.maxScrollExtent, 0);
          }
        });
      }
    }
  });
}
