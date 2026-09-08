import 'package:flutter/material.dart';
import '../models/project.dart';
import 'glass_card.dart';

class ProjectCard extends StatelessWidget {
  final Project project;
  final VoidCallback? onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onSync;
  final bool showSync;

  const ProjectCard({
    super.key,
    required this.project,
    this.onTap,
    this.onEdit,
    this.onSync,
    this.showSync = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final status = switch (project.status) {
      'completed' => (label: 'Completado', color: Colors.green),
      'analyzing' => (label: 'Analizando', color: Colors.orange),
      'error' => (label: 'Error', color: Colors.red),
      _ => (label: 'Pendiente', color: Colors.grey),
    };

    final qualityScore = project.stats?.qualityScore ?? 0;
    final qualityColor = qualityScore >= 70
        ? Colors.green
        : qualityScore >= 40
            ? Colors.orange
            : Colors.red;

    return GlassCard(
      padding: const EdgeInsets.all(12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with status badge and actions
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: status.color.withOpacity(0.12),
                  border: Border.all(
                    color: status.color.withOpacity(0.3),
                  ),
                ),
                child: Text(
                  status.label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: status.color,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
              // Action buttons
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (onEdit != null)
                    IconButton(
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  if (showSync && onSync != null)
                    IconButton(
                      onPressed: onSync,
                      icon: const Icon(Icons.sync, size: 16),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          
          // Project info
          InkWell(
            onTap: onTap,
            child: Row(
              children: [
                // Language icon
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10),
                    color: theme.colorScheme.primary.withOpacity(0.1),
                    border: Border.all(
                      color: theme.colorScheme.primary.withOpacity(0.2),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      _getLanguageIcon(project.language),
                      style: const TextStyle(fontSize: 18),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${project.language ?? 'Desconocido'} · ${_formatDate(project.createdAt)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontSize: 10,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          
          // Error message if exists
          if (project.hasError && project.errorMessage != null) ...[
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                color: Colors.red.withOpacity(0.1),
                border: Border.all(
                  color: Colors.red.withOpacity(0.2),
                ),
              ),
              child: Text(
                project.errorMessage!,
                style: TextStyle(
                  fontSize: 9,
                  color: Colors.red,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          
          // Quality bar for completed projects
          if (project.isCompleted) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  'Calidad',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 9,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(
                      value: qualityScore / 100,
                      backgroundColor: theme.colorScheme.outlineVariant.withOpacity(0.2),
                      valueColor: AlwaysStoppedAnimation<Color>(qualityColor),
                      minHeight: 4,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '$qualityScore%',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: qualityColor,
                  ),
                ),
              ],
            ),
          ],
          
          // Metrics
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMetric(
                theme,
                '${project.stats?.files ?? 0}',
                'Archivos',
              ),
              const SizedBox(width: 12),
              _buildMetric(
                theme,
                '${project.stats?.functions ?? 0}',
                'Funciones',
              ),
              const SizedBox(width: 12),
              _buildMetric(
                theme,
                '${project.stats?.endpoints ?? 0}',
                'Endpoints',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMetric(ThemeData theme, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontSize: 8,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }

  String _getLanguageIcon(String? language) {
    final icons = {
      'Python': '🐍',
      'JavaScript': '⚡',
      'TypeScript': '🔷',
      'Java': '☕',
      'PHP': '🐘',
      'Go': '🔵',
      'Ruby': '💎',
      'Dart': '🎯',
    };
    return icons[language] ?? '📄';
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}
