import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Seperti `list.animate(interval: ...)`, tapi jeda berhenti bertambah setelah [maxSteps] item.
///
/// Dengan `.animate(interval: 50.ms)` item ke-20 baru mulai muncul setelah 1 detik,
/// sehingga bagian bawah layar terlihat kosong saat di-scroll. Di sini item ke-6 dst.
/// memakai jeda yang sama, jadi tetap terasa berurutan tanpa menunggu lama.
class StaggerList extends ListBase<Widget> with AnimateManager<StaggerList> {
  StaggerList(List<Widget> children, {required Duration interval, int maxSteps = 6}) {
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      if (AnimateList.ignoreTypes.contains(child.runtimeType)) {
        _widgets.add(child);
        continue;
      }
      final animate = Animate(delay: interval * math.min(i, maxSteps), child: child);
      _managers.add(animate);
      _widgets.add(animate);
    }
  }

  final List<Widget> _widgets = [];
  final List<Animate> _managers = [];

  @override
  StaggerList addEffect(Effect effect) {
    for (final m in _managers) {
      m.addEffect(effect);
    }
    return this;
  }

  @override
  int get length => _widgets.length;

  @override
  set length(int length) => _widgets.length = length;

  @override
  Widget operator [](int index) => _widgets[index];

  @override
  void operator []=(int index, Widget value) => _widgets[index] = value;
}

extension StaggerListExtension on List<Widget> {
  StaggerList staggered({Duration interval = const Duration(milliseconds: 50), int maxSteps = 6}) =>
      StaggerList(this, interval: interval, maxSteps: maxSteps);
}
