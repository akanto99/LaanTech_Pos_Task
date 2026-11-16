import 'package:laantech_pos_task/model/transfer/transfer_task.dart';

enum TransferAction { enqueue, pause, resume, retry, cancel, remove, clearFinished, reset, sync }

/// Message sent from the UI isolate to the transfer engine.
class TransferCommand {
  final TransferAction action;
  final String? id;
  final List<TransferTask> tasks;

  const TransferCommand(this.action, {this.id, this.tasks = const []});

  factory TransferCommand.fromJson(Map<String, dynamic> json) => TransferCommand(
    TransferAction.values.byName(json['action'] as String),
    id: json['id'] as String?,
    tasks: (json['tasks'] as List<dynamic>? ?? []).map((task) => TransferTask.fromJson(Map<String, dynamic>.from(task as Map))).toList(),
  );

  Map<String, dynamic> toJson() => {'action': action.name, 'id': id, 'tasks': tasks.map((task) => task.toJson()).toList()};
}
