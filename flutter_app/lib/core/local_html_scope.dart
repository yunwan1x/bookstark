/// A storage namespace only, never an HTTP or cookie endpoint.
/// Preserve the existing database path spelling to retain recovery identities.
Uri localHtmlRecoveryScope(String databasePath) => Uri(
  scheme: 'https',
  host: 'bookstark-local.invalid',
  pathSegments: ['database', databasePath],
);
