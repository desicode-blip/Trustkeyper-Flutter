import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'move_in_screen.dart';

class TenancyPickerScreen extends StatelessWidget {
  const TenancyPickerScreen({
    required this.role,
    this.initialPage = 'checklist',
    super.key,
  });
  final String role;
  final String initialPage;
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        initialPage == 'notice'
            ? 'Start move-out'
            : initialPage == 'rent'
            ? 'Rent follow-up'
            : 'Move-in',
      ),
    ),
    body: StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, identity) {
        final uid = identity.data?.uid;
        if (uid == null) {
          return const Center(
            child: Text('Log in to choose your linked home.'),
          );
        }
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          key: ValueKey(uid),
          stream: FirebaseFirestore.instance
              .collection('agreements')
              .where('participantUids', arrayContains: uid)
              .snapshots(),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Homes could not be loaded. Check your account and connection.',
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final agreements = snapshot.data!.docs.where((document) {
              final agreement = document.data();
              final copy = agreement['agreementCopy'];
              return copy is Map &&
                  copy['mode'] == 'externally_signed' &&
                  copy['revision'] == agreement['revision'] &&
                  (role == 'broker'
                      ? agreement['brokerUid'] == uid
                      : (copy['people'] as List? ?? []).whereType<Map>().any(
                          (person) =>
                              person['uid'] == uid && person['role'] == role,
                        ));
            }).toList();
            return ListView(
              padding: const EdgeInsets.all(24),
              children: [
                const Text(
                  'Choose the home from its current signed agreement.',
                ),
                const SizedBox(height: 20),
                if (agreements.isEmpty)
                  const Text(
                    'No signed homes are linked yet. Demo copies cannot start move-in or move-out.',
                  ),
                for (final document in agreements)
                  Card(
                    child: ListTile(
                      title: Text(
                        document.data()['propertyAddress'] as String? ??
                            'Linked home',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) => MoveInScreen(
                            agreementId: document.id,
                            role: role,
                            initialPage: initialPage,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        );
      },
    ),
  );
}
