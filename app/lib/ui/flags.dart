import 'dart:math';

import 'package:flutter/material.dart';

import 'theme.dart';

/// A round country flag drawn in code. Windows has no flag emoji, and
/// drawn flags look the same on every platform.
class FlagBadge extends StatelessWidget {
  const FlagBadge({super.key, required this.code, this.size = 40});
  final String code;
  final double size;

  @override
  Widget build(BuildContext context) {
    final known = _flags.containsKey(code);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: GX.glassStrong,
        border: Border.all(color: GX.line),
        boxShadow: const [
          BoxShadow(
            color: Color(0x40000000),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipOval(
        child: known
            ? CustomPaint(painter: _FlagPainter(code))
            : Center(
                child: code.isEmpty
                    ? Icon(
                        Icons.public_rounded,
                        size: size * 0.5,
                        color: GX.muted,
                      )
                    : Text(
                        code,
                        style: body(size * 0.32, weight: 800, color: GX.accent),
                      ),
              ),
      ),
    );
  }
}

typedef _Draw = void Function(Canvas c, Size s);

const _white = Color(0xFFF4F6F8);
const _red = Color(0xFFD52B1E);
const _blue = Color(0xFF0039A6);

_Draw _rows(List<Color> colors, [List<double>? weights]) => (c, s) {
  final w = weights ?? List.filled(colors.length, 1.0);
  final total = w.reduce((a, b) => a + b);
  var y = 0.0;
  for (var i = 0; i < colors.length; i++) {
    final h = s.height * w[i] / total;
    c.drawRect(
      Rect.fromLTWH(0, y, s.width, h + 0.5),
      Paint()..color = colors[i],
    );
    y += h;
  }
};

_Draw _cols(List<Color> colors, [List<double>? weights]) => (c, s) {
  final w = weights ?? List.filled(colors.length, 1.0);
  final total = w.reduce((a, b) => a + b);
  var x = 0.0;
  for (var i = 0; i < colors.length; i++) {
    final cw = s.width * w[i] / total;
    c.drawRect(
      Rect.fromLTWH(x, 0, cw + 0.5, s.height),
      Paint()..color = colors[i],
    );
    x += cw;
  }
};

/// Scandinavian cross, shifted towards the hoist.
_Draw _nordic(Color bg, Color cross, [Color? inner]) => (c, s) {
  c.drawRect(Offset.zero & s, Paint()..color = bg);
  void bar(double t, Color color) {
    final p = Paint()..color = color;
    final cx = s.width * 0.4;
    c.drawRect(Rect.fromLTWH(0, s.height / 2 - t / 2, s.width, t), p);
    c.drawRect(Rect.fromLTWH(cx - t / 2, 0, t, s.height), p);
  }

  bar(s.height * 0.26, cross);
  if (inner != null) bar(s.height * 0.12, inner);
};

_Draw _centerCross(Color bg, Color cross, double t, double len) => (c, s) {
  c.drawRect(Offset.zero & s, Paint()..color = bg);
  final p = Paint()..color = cross;
  final ctr = s.center(Offset.zero);
  c.drawRect(
    Rect.fromCenter(center: ctr, width: s.width * len, height: s.height * t),
    p,
  );
  c.drawRect(
    Rect.fromCenter(center: ctr, width: s.width * t, height: s.height * len),
    p,
  );
};

_Draw _disc(Color bg, Color disc, double r) => (c, s) {
  c.drawRect(Offset.zero & s, Paint()..color = bg);
  c.drawCircle(
    s.center(Offset.zero),
    s.shortestSide * r,
    Paint()..color = disc,
  );
};

void _us(Canvas c, Size s) {
  _rows([
    for (var i = 0; i < 13; i++) i.isEven ? const Color(0xFFB22234) : _white,
  ])(c, s);
  c.drawRect(
    Rect.fromLTWH(0, 0, s.width * 0.48, s.height * 7 / 13),
    Paint()..color = const Color(0xFF3C3B6E),
  );
  final dot = Paint()..color = _white;
  for (var y = 0; y < 4; y++) {
    for (var x = 0; x < 4; x++) {
      c.drawCircle(
        Offset(s.width * (0.07 + x * 0.11), s.height * (0.07 + y * 0.12)),
        s.width * 0.018,
        dot,
      );
    }
  }
}

void _gb(Canvas c, Size s) {
  c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF012169));
  final w = s.width, h = s.height;
  final diag = Paint()
    ..color = _white
    ..strokeWidth = h * 0.2;
  c.drawLine(Offset.zero, Offset(w, h), diag);
  c.drawLine(Offset(w, 0), Offset(0, h), diag);
  diag
    ..color = const Color(0xFFC8102E)
    ..strokeWidth = h * 0.07;
  c.drawLine(Offset.zero, Offset(w, h), diag);
  c.drawLine(Offset(w, 0), Offset(0, h), diag);
  _crossOnly(c, s, _white, 0.3);
  _crossOnly(c, s, const Color(0xFFC8102E), 0.18);
}

void _crossOnly(Canvas c, Size s, Color color, double t) {
  final p = Paint()..color = color;
  c.drawRect(
    Rect.fromLTWH(0, s.height * (0.5 - t / 2), s.width, s.height * t),
    p,
  );
  c.drawRect(
    Rect.fromLTWH(s.width / 2 - s.height * t / 2, 0, s.height * t, s.height),
    p,
  );
}

void _tr(Canvas c, Size s) {
  const bg = Color(0xFFE30A17);
  c.drawRect(Offset.zero & s, Paint()..color = bg);
  final ctr = Offset(s.width * 0.42, s.height / 2);
  c.drawCircle(ctr, s.height * 0.25, Paint()..color = _white);
  c.drawCircle(
    ctr.translate(s.height * 0.06, 0),
    s.height * 0.2,
    Paint()..color = bg,
  );
  _star(c, Offset(s.width * 0.66, s.height / 2), s.height * 0.1, _white);
}

void _star(Canvas c, Offset ctr, double r, Color color) {
  final path = Path();
  for (var i = 0; i < 10; i++) {
    final rr = i.isEven ? r : r * 0.45;
    final a = -pi / 2 + i * pi / 5;
    final p = ctr + Offset(cos(a) * rr, sin(a) * rr);
    i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
  }
  c.drawPath(path..close(), Paint()..color = color);
}

void _cz(Canvas c, Size s) {
  _rows([_white, const Color(0xFFD7141A)])(c, s);
  c.drawPath(
    Path()
      ..moveTo(0, 0)
      ..lineTo(s.width * 0.5, s.height / 2)
      ..lineTo(0, s.height)
      ..close(),
    Paint()..color = const Color(0xFF11457E),
  );
}

void _ae(Canvas c, Size s) {
  _rows([const Color(0xFF00732F), _white, Colors.black])(c, s);
  c.drawRect(
    Rect.fromLTWH(0, 0, s.width * 0.28, s.height),
    Paint()..color = const Color(0xFFFF0000),
  );
}

void _kz(Canvas c, Size s) {
  c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFF00AFCA));
  c.drawCircle(
    s.center(Offset.zero),
    s.height * 0.2,
    Paint()..color = const Color(0xFFFEC50C),
  );
}

void _ge(Canvas c, Size s) {
  _centerCross(_white, const Color(0xFFFF0000), 0.2, 1)(c, s);
}

void _il(Canvas c, Size s) {
  _rows(
    [
      _white,
      const Color(0xFF0038B8),
      _white,
      _white,
      _white,
      const Color(0xFF0038B8),
      _white,
    ],
    [1, 1.2, 0.6, 2, 0.6, 1.2, 1],
  )(c, s);
}

void _in(Canvas c, Size s) {
  _rows([const Color(0xFFFF9933), _white, const Color(0xFF138808)])(c, s);
  c.drawCircle(
    s.center(Offset.zero),
    s.height * 0.12,
    Paint()
      ..color = const Color(0xFF000080)
      ..style = PaintingStyle.stroke
      ..strokeWidth = s.height * 0.03,
  );
}

final Map<String, _Draw> _flags = {
  'RU': _rows([_white, _blue, _red]),
  'DE': _rows([Colors.black, const Color(0xFFDD0000), const Color(0xFFFFCE00)]),
  'NL': _rows([const Color(0xFFAE1C28), _white, const Color(0xFF21468B)]),
  'FR': _cols([const Color(0xFF0055A4), _white, const Color(0xFFEF4135)]),
  'IT': _cols([const Color(0xFF009246), _white, const Color(0xFFCE2B37)]),
  'BE': _cols([Colors.black, const Color(0xFFFDDA24), const Color(0xFFEF3340)]),
  'RO': _cols([
    const Color(0xFF002B7F),
    const Color(0xFFFCD116),
    const Color(0xFFCE1126),
  ]),
  'MD': _cols([
    const Color(0xFF0046AE),
    const Color(0xFFFFD200),
    const Color(0xFFCC092F),
  ]),
  'IE': _cols([const Color(0xFF169B62), _white, const Color(0xFFFF883E)]),
  'CA': _cols(
    [const Color(0xFFD80621), _white, const Color(0xFFD80621)],
    [1, 2, 1],
  ),
  'PL': _rows([_white, const Color(0xFFDC143C)]),
  'UA': _rows([const Color(0xFF0057B7), const Color(0xFFFFD700)]),
  'EE': _rows([const Color(0xFF0072CE), Colors.black, _white]),
  'LT': _rows([
    const Color(0xFFFDB913),
    const Color(0xFF006A44),
    const Color(0xFFC1272D),
  ]),
  'LV': _rows(
    [const Color(0xFF9E3039), _white, const Color(0xFF9E3039)],
    [2, 1, 2],
  ),
  'AT': _rows([const Color(0xFFED2939), _white, const Color(0xFFED2939)]),
  'HU': _rows([const Color(0xFFCE2939), _white, const Color(0xFF477050)]),
  'BG': _rows([_white, const Color(0xFF00966E), const Color(0xFFD62612)]),
  'LU': _rows([const Color(0xFFEF3340), _white, const Color(0xFF00A3E0)]),
  'AM': _rows([
    const Color(0xFFD90012),
    const Color(0xFF0033A0),
    const Color(0xFFF2A800),
  ]),
  'RS': _rows([const Color(0xFFC6363C), const Color(0xFF0C4076), _white]),
  'BY': _rows([const Color(0xFFC8313E), const Color(0xFF4AA657)], [2, 1]),
  'ES': _rows(
    [const Color(0xFFAA151B), const Color(0xFFF1BF00), const Color(0xFFAA151B)],
    [1, 2, 1],
  ),
  'SG': _rows([const Color(0xFFEF3340), _white]),
  'FI': _nordic(_white, const Color(0xFF002F6C)),
  'SE': _nordic(const Color(0xFF006AA7), const Color(0xFFFECC02)),
  'DK': _nordic(const Color(0xFFC8102E), _white),
  'NO': _nordic(const Color(0xFFBA0C2F), _white, const Color(0xFF00205B)),
  'CH': _centerCross(const Color(0xFFDA291C), _white, 0.18, 0.62),
  'JP': _disc(_white, const Color(0xFFBC002D), 0.3),
  'HK': _disc(const Color(0xFFDE2910), _white, 0.22),
  'US': _us,
  'GB': _gb,
  'TR': _tr,
  'CZ': _cz,
  'AE': _ae,
  'KZ': _kz,
  'GE': _ge,
  'IL': _il,
  'IN': _in,
};

class _FlagPainter extends CustomPainter {
  _FlagPainter(this.code);
  final String code;

  @override
  void paint(Canvas canvas, Size size) {
    _flags[code]!(canvas, size);
    // A soft highlight so the flat colours read as a badge.
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0x33FFFFFF), Color(0x00FFFFFF), Color(0x26000000)],
        ).createShader(Offset.zero & size),
    );
  }

  @override
  bool shouldRepaint(_FlagPainter old) => old.code != code;
}
