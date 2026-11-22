enum LegacyGoIssueCode {
  unknownField,
  unknownEntry,
  editorTypeMissing,
  uploadsNotIncluded,
  missingUpload,
  uploadSizeMismatch,
  uploadHashMismatch,
  unreferencedUpload,
  unsupportedProtection,
  protectedContent,
  invalidIdentity,
  duplicateIdentity,
  unresolvedReference,
  ambiguousReference,
  cyclicHierarchy,
  unsupportedResourceKind,
}

/// Locations are fixed schema paths and row indices, never bodies or secrets.
final class LegacyGoIssue {
  const LegacyGoIssue(this.code, this.location);
  final LegacyGoIssueCode code;
  final String location;
}
