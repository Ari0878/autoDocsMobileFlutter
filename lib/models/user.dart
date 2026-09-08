class User {
  final String id;
  final String name;
  final String email;
  final String role;
  final String plan;
  final String? avatar;
  final DateTime createdAt;
  final int projectsCount;
  final int projectsLimit;

  User({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.plan,
    this.avatar,
    required this.createdAt,
    required this.projectsCount,
    required this.projectsLimit,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    DateTime createdAt;
    try {
      createdAt = json['createdAt'] != null || json['created_at'] != null
          ? DateTime.parse(json['createdAt'] ?? json['created_at'] ?? DateTime.now().toIso8601String())
          : DateTime.now();
    } catch (e) {
      createdAt = DateTime.now();
    }

    return User(
      id: json['id'] ?? json['_id'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? 'user',
      plan: json['plan'] ?? 'free',
      avatar: json['avatar'],
      createdAt: createdAt,
      projectsCount: json['projectsCount'] ?? json['projects_count'] ?? 0,
      projectsLimit: json['projectsLimit'] ?? json['projects_limit'] ?? 3,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'role': role,
      'plan': plan,
      'avatar': avatar,
      'createdAt': createdAt.toIso8601String(),
      'projectsCount': projectsCount,
      'projectsLimit': projectsLimit,
    };
  }

  User copyWith({
    String? id,
    String? name,
    String? email,
    String? role,
    String? plan,
    String? avatar,
    DateTime? createdAt,
    int? projectsCount,
    int? projectsLimit,
  }) {
    return User(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      role: role ?? this.role,
      plan: plan ?? this.plan,
      avatar: avatar ?? this.avatar,
      createdAt: createdAt ?? this.createdAt,
      projectsCount: projectsCount ?? this.projectsCount,
      projectsLimit: projectsLimit ?? this.projectsLimit,
    );
  }

  bool get canCreateProject => projectsCount < projectsLimit;
  bool get isAdmin => role == 'admin';
  bool get isFreePlan => plan == 'free';
}