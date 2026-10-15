import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class WorkflowUnavailable extends StatelessWidget {
  const WorkflowUnavailable({
    required this.title,
    required this.returnRoute,
    super.key,
  });
  final String title;
  final String returnRoute;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title)),
    body: Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.construction_outlined, size: 48),
            const SizedBox(height: 16),
            Text(
              'This workflow is not connected yet',
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            const Text(
              'No request, document, payment, approval or signature has been submitted. This feature is not ready for acceptance testing.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: () =>
                  context.canPop() ? context.pop() : context.go(returnRoute),
              child: const Text('Return'),
            ),
          ],
        ),
      ),
    ),
  );
}
