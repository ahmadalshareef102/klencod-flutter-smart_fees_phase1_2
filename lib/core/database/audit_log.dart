import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// يكتب سطرًا في سجل التدقيق. يُستدعى داخل نفس المعاملة المالية.
Future<void> writeAudit(
  DatabaseExecutor ex, {
  required String entity,
  required int? entityId,
  required String action,
  Map<String, Object?>? details,
  int? actorId,
}) async {
  await ex.insert('audit_logs', {
    'entity': entity,
    'entity_id': entityId,
    'action': action,
    'details': details == null ? null : jsonEncode(details),
    'actor_id': actorId,
  });
}
