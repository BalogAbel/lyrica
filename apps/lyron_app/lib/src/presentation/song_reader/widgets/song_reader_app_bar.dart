import 'package:flutter/material.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

/// App bar for the song reader screen: back button, title with an optional
/// effective-key subtitle, a warning indicator for recoverable parse
/// diagnostics, and a slot for the overflow menu.
class SongReaderAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SongReaderAppBar({
    super.key,
    required this.title,
    this.effectiveKey,
    required this.onBack,
    this.hasRecoverableWarnings = false,
    this.onShowWarnings,
    this.overflowMenu,
  });

  final String title;
  final String? effectiveKey;
  final VoidCallback onBack;
  final bool hasRecoverableWarnings;
  final VoidCallback? onShowWarnings;
  final Widget? overflowMenu;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: AppStrings.songReaderBackAction,
        onPressed: onBack,
        icon: const BackButtonIcon(),
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          if (effectiveKey != null)
            Builder(
              builder: (context) {
                final theme = Theme.of(context);
                return Text(
                  '${AppStrings.songReaderKeyLabelPrefix}$effectiveKey',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                );
              },
            ),
        ],
      ),
      actions: [
        if (hasRecoverableWarnings)
          IconButton(
            tooltip: AppStrings.songReaderWarningsSemantics,
            icon: const Icon(Icons.warning_amber_outlined),
            onPressed: onShowWarnings,
          ),
        ?overflowMenu,
      ],
    );
  }
}
