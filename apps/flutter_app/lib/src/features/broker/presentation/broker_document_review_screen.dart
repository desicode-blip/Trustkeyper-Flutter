import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/broker_document_context.dart';
import '../data/broker_updates_repository.dart';
import '../data/agreement_progress_repository.dart';
import '../data/agreement_draft_repository.dart';
import '../data/private_documents.dart';
import '../../document_requests/data/document_request_repository.dart';
import 'private_documents_screen.dart';

class BrokerDocumentReviewScreen extends StatefulWidget {
  const BrokerDocumentReviewScreen({
    required this.requestId,
    this.loadContext,
    this.onResume,
    super.key,
  });
  final String requestId;
  final Future<BrokerDocumentContext> Function()? loadContext;
  final ValueChanged<String>? onResume;
  @override
  State<BrokerDocumentReviewScreen> createState() =>
      _BrokerDocumentReviewScreenState();
}

class _BrokerDocumentReviewScreenState
    extends State<BrokerDocumentReviewScreen> {
  Future<BrokerDocumentContext> _load() async =>
      widget.loadContext?.call() ??
      loadBrokerDocumentContext(
        request: await FirebaseBrokerUpdatesRepository().request(
          widget.requestId,
        ),
        progressRepository: FirebaseAgreementProgressRepository(),
        loadCompleted: loadBrokerCompletedDocumentDraft,
      );
  late Future<BrokerDocumentContext> future = _load();
  bool redirecting = false;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Uploaded documents')),
    body: FutureBuilder<BrokerDocumentContext>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    snapshot.error is DocumentFailure
                        ? (snapshot.error as DocumentFailure).message
                        : snapshot.error is DraftFailure
                        ? (snapshot.error as DraftFailure).message
                        : 'Could not open these private documents. Check your connection.',
                  ),
                  TextButton(
                    onPressed: () => setState(() => future = _load()),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final value = snapshot.data!;
        if (value.progress != null) {
          if (!redirecting) {
            redirecting = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              if (widget.onResume != null) {
                widget.onResume!(value.resumePath);
              } else {
                context.replace(value.resumePath);
              }
            });
          }
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          children: [
            ListTile(
              title: Text(value.request.name),
              subtitle: Text(value.draft.propertyAddress),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: PrivateDocumentsScreen(
                  embedded: true,
                  draft: value.draft,
                  onlyPartyId: value.request.data['partyId'] as String,
                  requests: FirebaseDocumentRequests(),
                ),
              ),
            ),
          ],
        );
      },
    ),
  );
}
