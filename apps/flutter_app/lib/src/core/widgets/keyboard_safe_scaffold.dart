import 'package:flutter/material.dart';

class KeyboardSafeScaffold extends StatelessWidget {
  const KeyboardSafeScaffold({
    required this.child,
    super.key,
    this.appBar,
    this.padding = const EdgeInsets.fromLTRB(24, 20, 24, 32),
  });

  final PreferredSizeWidget? appBar;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    return Scaffold(
      appBar: appBar,
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: padding.copyWith(bottom: padding.bottom + keyboardInset),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight - padding.vertical,
                ),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}
