/// A translation issue a teacher logged while offline.
///
/// Kept compact on purpose: this is a record to be handed to the backend once
/// online, not a document. Timestamps let the sync layer show them in order.
class SupportReport {
  const SupportReport({
    required this.id,
    required this.message,
    required this.createdAt,
  });

  final String id;
  final String message;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'message': message,
        'createdAt': createdAt.toIso8601String(),
      };

  factory SupportReport.fromJson(Map<String, dynamic> json) => SupportReport(
        id: json['id'] as String,
        message: json['message'] as String,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );
}