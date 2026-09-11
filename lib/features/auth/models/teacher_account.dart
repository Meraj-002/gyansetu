import 'dart:convert';

/// The signed-in teacher, as far as the app needs to know them.
///
/// Deliberately small. Only what the UI has to show and what the sync layer has
/// to key on is kept on the device; anything else belongs on the server.
class TeacherAccount {
  const TeacherAccount({
    required this.id,
    required this.displayName,
    required this.schoolName,
    this.schoolCode,
    this.mobileLast4,
  });

  factory TeacherAccount.fromJson(Map<String, dynamic> json) {
    return TeacherAccount(
      id: json['id'] as String,
      displayName: json['displayName'] as String,
      schoolName: json['schoolName'] as String,
      schoolCode: json['schoolCode'] as String?,
      mobileLast4: json['mobileLast4'] as String?,
    );
  }

  static TeacherAccount? tryDecode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return TeacherAccount.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  /// Server-side identifier. Not the teacher's login ID.
  final String id;

  final String displayName;
  final String schoolName;
  final String? schoolCode;

  /// Last four digits only, so the PIN screen can show which number was used
  /// without the full number sitting on the device.
  final String? mobileLast4;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'displayName': displayName,
        'schoolName': schoolName,
        if (schoolCode != null) 'schoolCode': schoolCode,
        if (mobileLast4 != null) 'mobileLast4': mobileLast4,
      };

  String encode() => jsonEncode(toJson());

  TeacherAccount copyWith({
    String? displayName,
    String? schoolName,
    String? schoolCode,
    String? mobileLast4,
  }) {
    return TeacherAccount(
      id: id,
      displayName: displayName ?? this.displayName,
      schoolName: schoolName ?? this.schoolName,
      schoolCode: schoolCode ?? this.schoolCode,
      mobileLast4: mobileLast4 ?? this.mobileLast4,
    );
  }

  @override
  String toString() => 'TeacherAccount($id, $displayName)';
}
