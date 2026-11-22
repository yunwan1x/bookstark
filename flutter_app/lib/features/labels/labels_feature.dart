import 'package:flutter/material.dart';
import '../../core/draft_vault.dart';
import '../../core/label_management_repository.dart';
import 'labels_page.dart';
import 'label_detail_page.dart';
import 'label_merge_page.dart';
import 'label_recommendations_page.dart';

class LabelsFeature extends StatelessWidget {
  const LabelsFeature({
    super.key,
    required this.repository,
    required this.onOpenResource,
    this.initialLabelId,
    this.onRecoverCreations,
    this.drafts,
    this.english = false,
    this.local = false,
  });
  final int? initialLabelId;
  final Future<void> Function(BuildContext)? onRecoverCreations;
  final LabelManagementRepository repository;
  final Future<void> Function(BuildContext context, LabelResource resource)
  onOpenResource;
  final DraftVault? drafts;
  final bool english, local;
  Widget _detail(BuildContext context, int id) => LabelDetailPage(
    repository: repository,
    labelId: id,
    drafts: drafts,
    english: english,
    local: local,
    onOpenResource: (resource) => onOpenResource(context, resource),
  );
  @override
  Widget build(BuildContext context) => initialLabelId != null
      ? _detail(context, initialLabelId!)
      : LabelsPage(
          onRecoverCreation: onRecoverCreations == null
              ? null
              : () => onRecoverCreations!(context),
          repository: repository,
          drafts: drafts,
          english: english,
          local: local,
          onOpenLabel: (label) async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (context) => _detail(context, label.id),
              ),
            );
          },
          onMerge: (label) async {
            await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (_) => LabelMergePage(
                  repository: repository,
                  target: label,
                  english: english,
                  local: local,
                ),
              ),
            );
          },
          onRecommendations: () async {
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => LabelRecommendationsPage(
                  repository: repository,
                  english: english,
                  local: local,
                ),
              ),
            );
          },
        );
}
