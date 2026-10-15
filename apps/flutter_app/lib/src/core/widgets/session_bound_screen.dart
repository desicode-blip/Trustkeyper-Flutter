import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class SessionBoundScreen extends StatefulWidget {
  const SessionBoundScreen({
    required this.child,
    this.users,
    this.initialUid,
    this.expectedUid,
    this.onSessionEnded,
    super.key,
  });
  final Widget child;
  final Stream<String?>? users;
  final String? initialUid;
  final String? expectedUid;
  final VoidCallback? onSessionEnded;
  @override
  State<SessionBoundScreen> createState() => _SessionBoundScreenState();
}

class _SessionBoundScreenState extends State<SessionBoundScreen> {
  bool notified = false;
  late final users =
      widget.users ??
      FirebaseAuth.instance.userChanges().map((user) => user?.uid);
  late final initialUid = widget.users == null
      ? FirebaseAuth.instance.currentUser?.uid
      : widget.initialUid;
  @override
  Widget build(BuildContext context) => StreamBuilder<String?>(
    stream: users,
    initialData: initialUid,
    builder: (context, snapshot) {
      if (snapshot.hasError ||
          snapshot.data == null ||
          (widget.expectedUid != null && snapshot.data != widget.expectedUid)) {
        if (!notified && widget.onSessionEnded != null) {
          notified = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) widget.onSessionEnded?.call();
          });
        }
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Your session ended. Log in to reopen your private records.',
                  ),
                  TextButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Log in again'),
                  ),
                ],
              ),
            ),
          ),
        );
      }
      return KeyedSubtree(key: ValueKey(snapshot.data), child: widget.child);
    },
  );
}
