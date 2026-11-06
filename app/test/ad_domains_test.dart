import 'package:flutter_test/flutter_test.dart';
import 'package:gatex/routing/ad_domains.dart';

void main() {
  test('parseAdDomains cleans the v2fly format', () {
    final out = parseAdDomains(
      '# header\n'
      '\n'
      'Example.com\n'
      'domain:ads.net # trailing\n'
      'full:Track.Site.org\n'
      'tracker.io @ads\n'
      'regexp:^ad[0-9]+.com\n'
      'example.com\n'
      'DOMAIN:ads.net\n',
    );
    expect(out, ['example.com', 'ads.net', 'track.site.org', 'tracker.io']);
  });
}
