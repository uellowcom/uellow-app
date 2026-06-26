// =============================================================================
// ActivityTracker (v2.2.56) — customer journey tracking.
// Buffers lightweight events (screen open/leave with time-on-screen, app
// open/close, key actions) and flushes them in batches to
// POST /api/mobile/v2/track so the team can see exactly what a customer is
// doing. Best-effort: failures are swallowed, the buffer is bounded, and the
// network call never blocks the UI.
// =============================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../../api/uellow_api.dart';

class ActivityTracker {
  ActivityTracker._();
  static final ActivityTracker instance = ActivityTracker._();

  final List<Map<String, dynamic>> _buf = [];
  final Map<Route<dynamic>, DateTime> _enter = {};
  Timer? _timer;

  late final NavigatorObserver observer = _TrackerObserver(this);

  /// Start the periodic flush loop (call once at app start).
  void start() {
    _timer ??= Timer.periodic(
        const Duration(seconds: 20), (_) => unawaited(flush()));
  }

  void log(String event,
      {String? screen,
      String? label,
      String? refModel,
      int? refId,
      int? durationMs,
      Map<String, dynamic>? meta}) {
    _buf.add({
      'event': event,
      if (screen != null && screen.isNotEmpty) 'screen': screen,
      if (label != null && label.isNotEmpty) 'label': label,
      if (refModel != null) 'ref_model': refModel,
      if (refId != null) 'ref_id': refId,
      if (durationMs != null) 'duration_ms': durationMs,
      if (meta != null) 'meta': jsonEncode(meta),
      'ts': DateTime.now().millisecondsSinceEpoch,
    });
    // Bound the buffer; flush early when it grows.
    if (_buf.length >= 25) unawaited(flush());
    if (_buf.length > 200) _buf.removeRange(0, _buf.length - 200);
  }

  Future<void> flush() async {
    if (_buf.isEmpty) return;
    final batch = List<Map<String, dynamic>>.from(_buf);
    _buf.clear();
    try {
      await UellowApi.instance.postRaw('/api/mobile/v2/track',
          body: {'events': batch}, auth: true);
    } catch (_) {
      // best-effort analytics — drop on failure (don't requeue → no growth)
    }
  }

  String _name(Route<dynamic> r) {
    final n = r.settings.name;
    if (n != null && n.isNotEmpty) return n;
    return r.runtimeType.toString();
  }
}

class _TrackerObserver extends NavigatorObserver {
  _TrackerObserver(this.t);
  final ActivityTracker t;

  void _push(Route<dynamic> r) {
    t._enter[r] = DateTime.now();
    int? refId;
    final a = r.settings.arguments;
    if (a is Map && a['id'] is int) refId = a['id'] as int;
    t.log('screen_view', screen: t._name(r), refId: refId);
  }

  void _leave(Route<dynamic> r) {
    final e = t._enter.remove(r);
    final ms = e == null ? null : DateTime.now().difference(e).inMilliseconds;
    t.log('screen_leave', screen: t._name(r), durationMs: ms);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _push(route);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _leave(route);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is PageRoute) _leave(route);
  }
}
