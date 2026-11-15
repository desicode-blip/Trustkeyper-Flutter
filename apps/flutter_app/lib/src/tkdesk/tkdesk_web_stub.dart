/// Saves [text] as a file the person keeps. Phone build: not available.
bool downloadText(String name, String text) => false;

/// Opens the team's published, encrypted leads with the team password.
/// Returns the leads (TK Lead Format JSON) or null. Phone build: not available.
Future<String?> openPublishedLeads(String password, List<String> skip) async => null;

/// File names of the published lead batches (newest last). Phone build: none.
Future<List<String>> publishedBatches() async => const [];
