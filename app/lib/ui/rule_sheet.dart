import 'package:flutter/material.dart';

import '../routing/routing_settings.dart';
import 'theme.dart';

/// Pill-shaped choice between a few options, in the look of the app.
class SegmentedPick<T> extends StatelessWidget {
  const SegmentedPick({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  /// Option value and its label, in order.
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: GX.glass,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: GX.line),
      ),
      child: Row(
        children: [
          for (final (v, label) in options)
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(11),
                onTap: () => onChanged(v),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 4,
                  ),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(11),
                    color: v == value ? GX.accent : Colors.transparent,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: body(
                      13,
                      weight: 700,
                      color: v == value ? GX.accentInk : GX.muted,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom sheet that asks for one new own rule. Returns null when closed.
Future<RoutingRule?> showRuleSheet(BuildContext context) =>
    showModalBottomSheet<RoutingRule>(
      context: context,
      backgroundColor: GX.bg2,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const _RuleSheet(),
    );

class _RuleSheet extends StatefulWidget {
  const _RuleSheet();

  @override
  State<_RuleSheet> createState() => _RuleSheetState();
}

class _RuleSheetState extends State<_RuleSheet> {
  final _value = TextEditingController();
  var _kind = RuleKind.domain;
  var _action = RuleAction.proxy;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  String get _hint => switch (_kind) {
    RuleKind.domain => 'example.com',
    RuleKind.keyword => 'openai',
    RuleKind.ip => '203.0.113.0/24',
  };

  void _submit() {
    final v = _value.text.trim();
    if (v.isEmpty) return;
    Navigator.pop(context, RoutingRule(kind: _kind, value: v, action: _action));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          0,
          20,
          16 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Новое правило', style: display(18)),
              const SizedBox(height: 16),
              TextField(
                controller: _value,
                autofocus: true,
                autocorrect: false,
                keyboardType: TextInputType.url,
                style: mono(15),
                decoration: InputDecoration(hintText: _hint),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 14),
              SegmentedPick<RuleKind>(
                options: const [
                  (RuleKind.domain, 'Домен'),
                  (RuleKind.keyword, 'Ключевое слово'),
                  (RuleKind.ip, 'IP / подсеть'),
                ],
                value: _kind,
                onChanged: (v) => setState(() => _kind = v),
              ),
              const SizedBox(height: 10),
              SegmentedPick<RuleAction>(
                options: const [
                  (RuleAction.proxy, 'Через VPN'),
                  (RuleAction.direct, 'Напрямую'),
                  (RuleAction.block, 'Блокировать'),
                ],
                value: _action,
                onChanged: (v) => setState(() => _action = v),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ListenableBuilder(
                  listenable: _value,
                  builder: (_, _) => FilledButton(
                    onPressed: _value.text.trim().isEmpty ? null : _submit,
                    child: const Text('Добавить'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
