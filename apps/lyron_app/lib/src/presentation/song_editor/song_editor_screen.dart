import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:lyron_app/src/application/providers.dart';
import 'package:lyron_app/src/application/song_library/song_mutation_sync_types.dart';
import 'package:lyron_app/src/domain/core/capability.dart';
import 'package:lyron_app/src/presentation/song_editor/browser_unsaved_changes_guard.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_controller.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_projection.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_selection.dart';
import 'package:lyron_app/src/presentation/song_editor/song_editor_state.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_body.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_dialogs.dart';
import 'package:lyron_app/src/presentation/song_editor/widgets/song_editor_tab_bar.dart';
import 'package:lyron_app/src/router/app_routes.dart';
import 'package:lyron_app/src/shared/app_strings.dart';

class SongEditorScreen extends ConsumerStatefulWidget {
  const SongEditorScreen.edit({
    super.key,
    required String songId,
    required String songSlug,
    String? initialSource,
  }) : _songId = songId,
       _songSlug = songSlug,
       _initialSource = initialSource,
       _isCreating = false;

  const SongEditorScreen.create({super.key})
    : _songId = null,
      _songSlug = null,
      _initialSource = null,
      _isCreating = true;

  final String? _songId;
  final String? _songSlug;
  final String? _initialSource;
  final bool _isCreating;

  @override
  ConsumerState<SongEditorScreen> createState() => _SongEditorScreenState();
}

class _SongEditorScreenState extends ConsumerState<SongEditorScreen> {
  static const _sourceSample = SongEditorController.defaultSource;

  final SongEditorController _controller = SongEditorController();
  late final TextEditingController _sourceController;
  SongEditorTab _tabletTab = SongEditorTab.source;
  String _savedSource = _sourceSample;
  bool _isDirty = false;

  @override
  void initState() {
    super.initState();
    final seedSource = widget._initialSource ?? _sourceSample;
    _controller.setSource(seedSource);
    _sourceController = TextEditingController(text: seedSource);
    _savedSource = seedSource;
    _isDirty = false;
  }

  @override
  void didUpdateWidget(covariant SongEditorScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextSource = widget._initialSource;
    if (nextSource == null ||
        nextSource == oldWidget._initialSource ||
        _isDirty) {
      return;
    }

    if (nextSource != _controller.state.source) {
      _controller.setSource(nextSource);
      _sourceController.text = nextSource;
      _savedSource = nextSource;
      _isDirty = false;
    }
  }

  @override
  void dispose() {
    BrowserUnsavedChangesGuard.setEnabled(false);
    _sourceController.dispose();
    super.dispose();
  }

  void _setDirty(bool isDirty) {
    _isDirty = isDirty;
    BrowserUnsavedChangesGuard.setEnabled(isDirty);
  }

  void _setSource(String source) {
    setState(() {
      _controller.setSource(source);
      _setDirty(true);
    });
  }

  void _transposeDown() {
    setState(() {
      final previousSource = _sourceController.text;
      final previousSelection = _sourceController.selection;
      _controller.transposeDown();
      _syncSourceControllerText(
        previousSource: previousSource,
        previousSelection: previousSelection,
      );
      _setDirty(true);
    });
  }

  void _transposeUp() {
    setState(() {
      final previousSource = _sourceController.text;
      final previousSelection = _sourceController.selection;
      _controller.transposeUp();
      _syncSourceControllerText(
        previousSource: previousSource,
        previousSelection: previousSelection,
      );
      _setDirty(true);
    });
  }

  void _capoDown() {
    setState(() {
      final previousSource = _sourceController.text;
      final previousSelection = _sourceController.selection;
      _controller.capoDown();
      _syncSourceControllerText(
        previousSource: previousSource,
        previousSelection: previousSelection,
      );
      _setDirty(true);
    });
  }

  void _capoUp() {
    setState(() {
      final previousSource = _sourceController.text;
      final previousSelection = _sourceController.selection;
      _controller.capoUp();
      _syncSourceControllerText(
        previousSource: previousSource,
        previousSelection: previousSelection,
      );
      _setDirty(true);
    });
  }

  void _syncSourceControllerText({
    required String previousSource,
    required TextSelection previousSelection,
  }) {
    final nextSource = _controller.state.source;
    _sourceController.value = TextEditingValue(
      text: nextSource,
      selection: preserveSelectionAfterSourceRewrite(
        previousSource: previousSource,
        nextSource: nextSource,
        previousSelection: previousSelection,
      ),
    );
  }

  void _commitChanges() {
    setState(() {
      _savedSource = _controller.state.source;
      _setDirty(false);
    });
  }

  void _cancelChanges() {
    setState(() {
      _controller.setSource(_savedSource);
      _sourceController.text = _savedSource;
      _setDirty(false);
    });
  }

  String _songViewLocation() {
    return AppRoutes.songReader.path.replaceFirst(
      ':songSlug',
      widget._songSlug ?? '',
    );
  }

  void _returnToSongView(BuildContext context) {
    _cancelChanges();
    if (widget._isCreating) {
      if (context.canPop()) {
        context.pop();
        return;
      }
      context.go(AppRoutes.home.path);
      return;
    }
    context.replace(_songViewLocation());
  }

  Future<void> _cancelAndReturn(BuildContext context) async {
    if (!await _confirmDiscardChangesIfNeeded(context)) {
      return;
    }

    if (!context.mounted) {
      return;
    }
    _returnToSongView(context);
  }

  Future<void> _saveAndReturn(BuildContext context) async {
    final activeContext = ref.read(activeCatalogContextProvider);
    if (activeContext == null) {
      _returnToSongView(context);
      return;
    }

    final service = ref.read(songLibraryServiceProvider);
    final projection = SongEditorProjection(state: _controller.state);

    if (widget._isCreating) {
      final record = await service.createSong(
        context: activeContext,
        title: projection.summaryTitle,
        chordproSource: _controller.state.source,
      );

      if (!context.mounted) {
        return;
      }

      ref.invalidate(songLibraryListProvider);
      ref.invalidate(songMutationEntriesProvider);
      _commitChanges();
      context.replace(
        AppRoutes.songReader.path.replaceFirst(':songSlug', record.slug),
      );
      return;
    }

    final songId = widget._songId!;
    final songViewLocation = _songViewLocation();

    try {
      await service.updateSong(
        context: activeContext,
        songId: songId,
        title: projection.summaryTitle,
        chordproSource: _controller.state.source,
      );
    } on SongConflictResolutionRequiredException {
      if (!context.mounted) {
        return;
      }
      await showSongEditorConflictDialog(context);
      return;
    }

    if (!context.mounted) {
      return;
    }

    ref.invalidate(songLibraryListProvider);
    ref.invalidate(songMutationEntriesProvider);
    ref.invalidate(songLibraryReaderProvider(songId));
    _commitChanges();
    context.replace(songViewLocation);
  }

  Future<bool> _confirmDiscardChangesIfNeeded(BuildContext context) async {
    if (!_isDirty) {
      return true;
    }

    return confirmDiscardSongEditorChanges(context);
  }

  Future<void> _handleBack(BuildContext context) async {
    if (!await _confirmDiscardChangesIfNeeded(context)) {
      return;
    }

    if (!context.mounted) {
      return;
    }

    _cancelChanges();

    if (context.canPop()) {
      context.pop();
      return;
    }

    if (widget._isCreating) {
      context.go(AppRoutes.home.path);
      return;
    }

    context.replace(_songViewLocation());
  }

  void _setCanonicalView(SongEditorCanonicalViewMode mode) {
    setState(() {
      _controller.setCanonicalViewMode(mode);
      _tabletTab = switch (mode) {
        SongEditorCanonicalViewMode.source => SongEditorTab.source,
        SongEditorCanonicalViewMode.preview => SongEditorTab.preview,
      };
    });
  }

  void _setTabletTab(SongEditorTab tab) {
    setState(() {
      _tabletTab = tab;
      if (tab == SongEditorTab.source) {
        _controller.setCanonicalViewMode(SongEditorCanonicalViewMode.source);
      } else if (tab == SongEditorTab.preview) {
        _controller.setCanonicalViewMode(SongEditorCanonicalViewMode.preview);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final projection = SongEditorProjection(state: _controller.state);
    final orgId = ref.watch(activeCatalogContextProvider)?.organizationId;

    // Guard against direct deep-links or capability downgrade mid-session.
    // Fail-open when orgId or resolver are unavailable (consistent with
    // IfCapability's fail-open contract — backend enforces the actual check).
    if (orgId != null) {
      bool canEdit = true;
      try {
        canEdit =
            ref
                .watch(capabilityResolverProvider)
                .hasCapabilitySync(orgId, Capability.editSongs) ??
            true;
      } catch (_) {}
      if (!canEdit) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) context.pop();
        });
        return const SizedBox.shrink();
      }
    }

    return SongEditorBody(
      title: widget._isCreating
          ? AppStrings.songCreateTitle
          : AppStrings.songEditAction,
      isDirty: _isDirty,
      organizationId: orgId,
      projection: projection,
      sourceController: _sourceController,
      canonicalViewMode: _controller.state.canonicalViewMode,
      selectedTab: _tabletTab,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        unawaited(_handleBack(context));
      },
      onBack: () => unawaited(_handleBack(context)),
      onSave: () => _saveAndReturn(context),
      onCancel: () => unawaited(_cancelAndReturn(context)),
      onSourceChanged: _setSource,
      onTransposeDown: _transposeDown,
      onTransposeUp: _transposeUp,
      onCapoDown: _capoDown,
      onCapoUp: _capoUp,
      onCanonicalViewChanged: _setCanonicalView,
      onSelectedTab: _setTabletTab,
    );
  }
}
