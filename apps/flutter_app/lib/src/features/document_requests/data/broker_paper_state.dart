import '../../broker/data/private_documents.dart';
import 'document_request_repository.dart';

class BrokerPaperState {
  const BrokerPaperState({
    required this.paper,
    required this.request,
    required this.localKinds,
  });
  final RequestedPaper paper;
  final DocumentRequestInfo? request;
  final Set<DocumentKind> localKinds;

  static List<BrokerPaperState> resolve(
    List<DocumentRequestInfo> records,
    Set<DocumentKind> localKinds, {
    bool includeLinkedIn = false,
  }) =>
      [
        ...RequestedPaper.individual,
        if (includeLinkedIn) RequestedPaper.linkedin,
      ].map((paper) {
        final candidates =
            records
                .where(
                  (record) =>
                      record.paper.papers.contains(paper) ||
                      paper == RequestedPaper.linkedin &&
                          record.paper == RequestedPaper.all &&
                          record.submission?['linkedInDetails'] != null,
                )
                .toList()
              ..sort((first, second) {
                final ordering = _changedAt(
                  first,
                  paper,
                ).compareTo(_changedAt(second, paper));
                return ordering != 0
                    ? ordering
                    : first.paper == paper
                    ? 1
                    : -1;
              });
        return BrokerPaperState(
          paper: paper,
          request: candidates.isEmpty ? null : candidates.last,
          localKinds: localKinds,
        );
      }).toList();

  static int _changedAt(DocumentRequestInfo request, RequestedPaper paper) {
    final closed = request.closedPapers[paper.name] as Map?;
    final closedAt = (closed?['atMs'] as num?)?.toInt() ?? 0;
    return closedAt > request.issuedAtMs ? closedAt : request.issuedAtMs;
  }

  bool get local =>
      paper != RequestedPaper.linkedin &&
      paper.slots.every(localKinds.contains);
  bool get partial => !local && paper.slots.any(localKinds.contains);
  String? get closedAction =>
      (request?.closedPapers[paper.name] as Map?)?['action'] as String?;
  bool get received {
    if (request?.status != 'added' || closedAction != null) return false;
    final submission = request?.submission;
    if (paper == RequestedPaper.linkedin) {
      return submission?['linkedInDetails'] != null;
    }
    if (paper == RequestedPaper.bank && submission?['bankDetails'] != null) {
      return true;
    }
    return paper.slots.every(
      (kind) => (submission?['files'] as Map?)?.containsKey(kind.name) == true,
    );
  }

  bool get skipped =>
      paper == RequestedPaper.linkedin &&
      received &&
      (request?.submission?['linkedInDetails'] as Map?)?['skipped'] == true;
  bool get done => local || received && !skipped;
  bool get deleted => !done && closedAction == 'paper_deleted';
  bool get unclear =>
      !done && closedAction == null && request?.status == 'unclear';
  bool get expired =>
      !done && !skipped && closedAction == null && request?.expired == true;
  bool get waiting =>
      !done &&
      closedAction == null &&
      !expired &&
      ['shared', 'seen', 'finalizing'].contains(request?.status);
  bool get sent => request != null && request!.sharedAtMs > 0;
  bool get problem => unclear || expired;
  String get firstName => request?.name.split(' ').first ?? '';
  String get signature =>
      '${request?.id}/${request?.version}/${request?.status}/${request?.submission?['uploadId']}/$closedAction/$local/$partial';

  String label(DateTime now) {
    if (local) {
      return paper == RequestedPaper.bank
          ? 'Added · cheque added'
          : 'Added by you';
    }
    if (received) {
      if (paper == RequestedPaper.linkedin) {
        final profile = request?.submission?['linkedInDetails'] as Map;
        return profile['skipped'] == true
            ? 'Skipped · can add later'
            : 'Added · ${Uri.parse(profile['url'] as String).path.substring(1)}';
      }
      if (paper == RequestedPaper.bank) {
        return request?.submission?['bankDetails'] == null
            ? 'Added · cheque added'
            : 'Added · details added';
      }
      return 'Added by $firstName';
    }
    if (deleted) return 'Deleted · add again';
    if (partial) {
      return localKinds.contains(DocumentKind.aadhaarFront)
          ? 'Front added · add back'
          : 'Back added · add front';
    }
    if (unclear) return 'Photo not clear';
    if (expired) return 'Link expired';
    if (request?.status == 'finalizing') return 'Upload is being checked';
    if (request?.status == 'seen') return 'Seen · not added yet';
    if (waiting) {
      final ago = relativeTime(request!.sharedAtMs, now);
      return switch (request!.channel) {
        'SMS' => 'Sent by SMS · $ago',
        'Email' => 'Sent by email · $ago',
        _ => 'Waiting · sent $ago',
      };
    }
    if (request?.status == 'created') return 'Link ready · not sent';
    return paper == RequestedPaper.linkedin ? 'Optional · tenant can skip' : '';
  }

  static String relativeTime(int atMs, DateTime now) {
    final seconds = ((now.millisecondsSinceEpoch - atMs) ~/ 1000).clamp(
      0,
      1 << 30,
    );
    if (seconds < 60) return 'just now';
    if (seconds < 3600) return '${seconds ~/ 60} min ago';
    if (seconds < 86400) return '${seconds ~/ 3600} hr ago';
    return '${seconds ~/ 86400} days ago';
  }
}
