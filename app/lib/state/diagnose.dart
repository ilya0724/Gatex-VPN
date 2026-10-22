/// One line of the app's journal.
class JournalEntry {
  JournalEntry(this.time, this.text, {this.error = false});
  final DateTime time;
  final String text;
  final bool error;

  @override
  String toString() {
    String two(int n) => n.toString().padLeft(2, '0');
    final t = '${two(time.hour)}:${two(time.minute)}:${two(time.second)}';
    return '$t ${error ? '✕' : '·'} $text';
  }
}

/// Why a server failed its delay test: a short Russian reason for the
/// list, and the core's own words for the journal and support.
class DelayFailure {
  const DelayFailure(this.summary, this.detail);
  final String summary;
  final String detail;

  factory DelayFailure.from(String raw) {
    final t = raw.toLowerCase();
    bool has(String s) => t.contains(s);
    final summary = has('reality')
        ? 'Reality не принял ключ или SNI'
        : has('x509') || has('certificate')
        ? 'Ошибка сертификата TLS'
        : has('connection refused') || has('actively refused')
        ? 'Порт сервера закрыт'
        : has('no such host') || has('lookup')
        ? 'Не найден адрес сервера'
        : has('network is unreachable') || has('no route')
        ? 'Нет маршрута до сервера'
        : has('connection reset') || has('forcibly closed')
        ? 'Соединение сброшено, возможна блокировка'
        : has('timeout') || has('deadline exceeded')
        ? 'Сервер не ответил вовремя'
        : has('tls') || has('handshake')
        ? 'Ошибка TLS-рукопожатия'
        : has('probe answered')
        ? 'Сервер ответил ошибкой'
        : has('eof') || has('closed')
        ? 'Сервер закрыл соединение'
        : 'Нет ответа';
    return DelayFailure(summary, raw.trim());
  }
}
