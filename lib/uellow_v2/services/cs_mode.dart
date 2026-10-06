// Shared live-Customer-Service mode flag. When ON, Beena's entry icons
// (bottom-nav tab, product-page help button) and the chat persona switch to
// the human-support look. Fetched from /cs/status and cached reactively.
import 'package:flutter/foundation.dart';

import '../../api/uellow_api.dart';

class CsMode {
  CsMode._();
  static final CsMode instance = CsMode._();

  final ValueNotifier<bool> active = ValueNotifier<bool>(false);
  bool _loading = false;

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    try {
      final r = await UellowApi.instance.getRaw('/api/mobile/v2/cs/status');
      final v = (r['data'] as Map?)?['cs_mode'] == true;
      if (active.value != v) active.value = v;
    } catch (_) {} finally {
      _loading = false;
    }
  }

  void set(bool v) {
    if (active.value != v) active.value = v;
  }
}
