import 'package:lumen_core/lumen_core.dart';
void main() {
  final r = Lexicon.parse('cinematic');
  for (final c in r.clauses) { print('${c.text} ${c.atoms} ${c.ops.map((o) => o is SetOp ? 'set ${o.param}=${o.value}' : o is DeltaOp ? 'd ${o.param}=${o.delta}' : o.runtimeType)}'); }
  print(r.apply(DevelopSettings.defaults).settings);
}
