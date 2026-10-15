import 'package:flutter/material.dart';

class AppBrand extends StatelessWidget {
  const AppBrand({super.key, this.height = 42, this.markOnly = false});

  final double height;
  final bool markOnly;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      markOnly
          ? 'assets/images/trustkeyper-mark.png'
          : 'assets/images/trustkeyper-logo-approved.png',
      height: height,
      fit: BoxFit.contain,
      alignment: Alignment.centerLeft,
      semanticLabel: 'TrustKeyper',
    );
  }
}
