class Project {
  final String id;
  final String name;
  final String? description;
  final String status; // 'completed', 'analyzing', 'pending', 'error'
  final String? language;
  final DateTime createdAt;
  final ProjectStats? stats;
  final String? errorMessage;
  final String? githubUrl;

  Project({
    required this.id,
    required this.name,
    this.description,
    required this.status,
    this.language,
    required this.createdAt,
    this.stats,
    this.errorMessage,
    this.githubUrl,
  });

  factory Project.fromJson(Map<String, dynamic> json) {
    return Project(
      id: json['_id'] ?? json['id'] ?? '',
      name: json['name'] ?? 'Sin nombre',
      description: json['description'],
      status: json['status'] ?? 'pending',
      language: json['language'],
      createdAt: DateTime.parse(json['created_at'] ?? json['createdAt'] ?? DateTime.now().toIso8601String()),
      stats: json['stats'] != null ? ProjectStats.fromJson(json['stats']) : null,
      errorMessage: json['error_message'] ?? json['error'],
      githubUrl: json['github_url'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      '_id': id,
      'name': name,
      'description': description,
      'status': status,
      'language': language,
      'created_at': createdAt.toIso8601String(),
      'stats': stats?.toJson(),
      'error_message': errorMessage,
      'github_url': githubUrl,
    };
  }

  bool get isCompleted => status == 'completed';
  bool get isAnalyzing => status == 'analyzing';
  bool get isPending => status == 'pending';
  bool get hasError => status == 'error';
}

class ProjectStats {
  final int files;
  final int functions;
  final int endpoints;
  final int? qualityScore;

  ProjectStats({
    this.files = 0,
    this.functions = 0,
    this.endpoints = 0,
    this.qualityScore,
  });

  factory ProjectStats.fromJson(Map<String, dynamic> json) {
    return ProjectStats(
      files: json['files'] ?? 0,
      functions: json['functions'] ?? 0,
      endpoints: json['endpoints'] ?? 0,
      qualityScore: json['quality_score'] ?? json['qualityScore'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'files': files,
      'functions': functions,
      'endpoints': endpoints,
      'quality_score': qualityScore,
    };
  }
}