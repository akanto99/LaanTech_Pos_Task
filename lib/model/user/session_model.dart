class SessionModel {
  final String token;
  final String username;
  final DateTime expiresAt;

  const SessionModel({
    required this.token,
    required this.username,
    required this.expiresAt,
  });

  bool get isExpired => !DateTime.now().isBefore(expiresAt);

  factory SessionModel.fromJson(Map<String, dynamic> json) => SessionModel(
    token: json['token'] as String,
    username:
        (json['user'] as Map<String, dynamic>?)?['username'] as String? ?? '',
    expiresAt: DateTime.now().add(
      Duration(seconds: (json['expires_in'] as num?)?.toInt() ?? 0),
    ),
  );
}
