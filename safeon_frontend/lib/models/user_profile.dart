class UserProfile {
  const UserProfile({
    required this.id,
    required this.email,
    required this.name,
    this.registeredAt,
  });

  final String id;
  final String email;
  final String name;
  final DateTime? registeredAt;

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] as String,
      email: json['email'] as String,
      name: json['name'] as String? ?? 'SafeOn 사용자',
      registeredAt: json['registeredAt'] != null
          ? DateTime.tryParse(json['registeredAt'] as String)
          : null,
    );
  }

  UserProfile copyWith({
    String? name,
    String? email,
  }) {
    return UserProfile(
      id: id,
      email: email ?? this.email,
      name: name ?? this.name,
      registeredAt: registeredAt,
    );
  }
}