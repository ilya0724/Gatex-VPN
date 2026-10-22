import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'subscription.dart';

/// What the app tells the panel about this device. Remnawave uses the
/// x-hwid headers for its device limit.
class DeviceInfo {
  const DeviceInfo({
    required this.appVersion,
    required this.hwid,
    required this.model,
  });

  final String appVersion;
  final String hwid;
  final String model;

  String get os => Platform.isAndroid
      ? 'Android'
      : Platform.isWindows
      ? 'Windows'
      : 'Linux';

  Map<String, String> get headers => {
    'User-Agent': 'GateX/$appVersion ($os)',
    'x-hwid': hwid,
    'x-device-os': os,
    'x-ver-os': Platform.operatingSystemVersion,
    'x-device-model': model,
    'Accept': '*/*',
  };
}

class SubscriptionException implements Exception {
  SubscriptionException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Raw response kept so the subscription can be rebuilt offline.
class RawSubscription {
  RawSubscription(this.url, this.headers, this.body, this.fetchedAt);
  final String url;
  final Map<String, String> headers;
  final String body;
  final DateTime fetchedAt;

  Subscription parse() => parseSubscription(
    url: url,
    headers: headers,
    body: body,
    fetchedAt: fetchedAt,
  );
}

Future<RawSubscription> fetchSubscription(String url, DeviceInfo device) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null || !uri.hasScheme || !uri.scheme.startsWith('http')) {
    throw SubscriptionException('Это не похоже на ссылку подписки');
  }
  final http.Response resp;
  try {
    resp = await http
        .get(uri, headers: device.headers)
        .timeout(const Duration(seconds: 20));
  } on Exception {
    throw SubscriptionException(
      'Не удалось загрузить подписку. Проверьте интернет и попробуйте ещё раз',
    );
  }
  if (resp.statusCode == 404) {
    throw SubscriptionException(
      'Подписка не найдена. Возьмите новую ссылку в боте',
    );
  }
  if (resp.statusCode != 200) {
    throw SubscriptionException(
      'Сервер подписки ответил ошибкой ${resp.statusCode}',
    );
  }
  final raw = RawSubscription(
    url.trim(),
    resp.headers,
    // Panels do not always declare a charset; names are UTF-8.
    utf8.decode(resp.bodyBytes, allowMalformed: true),
    DateTime.now(),
  );
  final sub = raw.parse();
  if (sub.servers.isEmpty && sub.notices.isEmpty) {
    throw SubscriptionException('В подписке нет серверов');
  }
  return raw;
}
