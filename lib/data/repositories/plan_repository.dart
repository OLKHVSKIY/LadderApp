import 'dart:convert';

import 'package:drift/drift.dart' as dr;

import '../app_database.dart';
import '../../models/goal_model.dart';

class PlanRepository {
  final AppDatabase db;
  PlanRepository(this.db);

  Future<int> saveGoal(GoalModel goal, int userId) async {
    final jsonStr = jsonEncode(goal.toMap(excludeDbId: true));
    if (goal.dbId != null) {
      await (db.update(db.plans)..where((p) => p.id.equals(goal.dbId!))).write(
        PlansCompanion(
          title: dr.Value(goal.title),
          description: dr.Value(jsonStr),
          updatedAt: dr.Value(DateTime.now()),
        ),
      );
      return goal.dbId!;
    } else {
      return db.into(db.plans).insert(
            PlansCompanion.insert(
              userId: userId,
              title: goal.title,
              description: dr.Value(jsonStr),
              createdAt: dr.Value(DateTime.now()),
              updatedAt: dr.Value(DateTime.now()),
            ),
          );
    }
  }

  Future<void> deleteGoal(int dbId) async {
    await (db.delete(db.plans)..where((p) => p.id.equals(dbId))).go();
  }

  Future<List<GoalModel>> loadGoals(int userId) async {
    final rows = await (db.select(db.plans)
          ..where((p) => p.userId.equals(userId))
          ..orderBy([(p) => dr.OrderingTerm.desc(p.updatedAt)]))
        .get();
    final result = <GoalModel>[];
    for (final r in rows) {
      try {
        final map = r.description != null ? jsonDecode(r.description!) as Map<String, dynamic> : null;
        if (map == null) continue;
        final goal = GoalModel.fromMap(map).copyWith(dbId: r.id, isSaved: true, isActive: false);
        result.add(goal);
      } catch (_) {
        // skip malformed entry
      }
    }
    return result;
  }
}

