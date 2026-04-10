import 'package:flutter/material.dart';

import '../../main.dart';

class LoadingView extends StatelessWidget {
  const LoadingView();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(
              color: AppTheme.blue,
              strokeWidth: 2.5,
            ),
          ),
          SizedBox(height: 20),
          Text(
            'Initialising…',
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 14,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }
}