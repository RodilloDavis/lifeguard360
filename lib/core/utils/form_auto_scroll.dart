// lib/core/utils/form_auto_scroll.dart
//
// ═══════════════════════════════════════════════════════════════════════════════
// STEP-BY-STEP AUTO-SCROLL FOR THE EMERGENCY REPORT FORMS
// ═══════════════════════════════════════════════════════════════════════════════
//
// Every emergency form is one long scrolling column of questions. Answering one
// used to leave the next question below the fold, so the reporter had to stop
// and scroll between every tap — in the middle of an emergency, which is the
// worst possible time to ask someone to hunt for the next control.
//
// This mixin moves the form on for them: pick an option, and the next question
// slides into view; answer the last one, and the send button does.
//
// Usage:
//   class _XState extends State<X> with AutoScrollForm<X> {
//     @override
//     List<Object> get autoScrollSteps => const ['type', 'trapped', 'send'];
//
//     // in build(), wrap each question (its title AND its control) —
//     autoScrollStep('trapped', Column(children: [title, control]))
//
//     // in each option's handler —
//     onTap: () { setState(...); advanceFrom('type'); }
//   }
//
// Steps that aren't currently in the widget tree — a follow-up question that
// only appears after a particular answer, say — are skipped automatically, so
// the chain always lands on the next question the user can actually see.

import 'package:flutter/material.dart';

mixin AutoScrollForm<T extends StatefulWidget> on State<T> {
  /// The form's questions in the order they appear, ending with the id of the
  /// submit button. Ids only have to be unique within one form.
  List<Object> get autoScrollSteps;

  final Map<Object, GlobalKey> _stepKeys = {};

  static const Duration _scrollDuration = Duration(milliseconds: 450);
  static const Curve _scrollCurve = Curves.easeInOutCubic;

  /// Questions settle near the top of the viewport, with the rest of the form
  /// visible below them.
  static const double _questionAlignment = 0.08;

  /// The submit button settles near the BOTTOM instead, so whatever sits just
  /// above it — an optional notes field, safety reminders — stays on screen
  /// rather than being scrolled past unseen.
  static const double _submitAlignment = 0.9;

  /// Wraps one question so it can be scrolled to. Include the section title
  /// along with its control, or the form lands on bare buttons with the
  /// question they answer left off the top of the screen.
  Widget autoScrollStep(Object id, Widget child) => KeyedSubtree(
        key: _stepKeys.putIfAbsent(id, () => GlobalKey()),
        child: child,
      );

  /// Call after the user answers the step [id]: brings the next question that
  /// is actually on screen into view, or the submit button when [id] was the
  /// last question.
  void advanceFrom(Object id) {
    final steps = autoScrollSteps;
    final from = steps.indexOf(id);
    if (from < 0) return;

    // Deferred a frame because the answer just given may itself have revealed
    // the next step (e.g. picking "Yes" adds a follow-up question) — that
    // widget has no context to scroll to until this frame is laid out.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (var i = from + 1; i < steps.length; i++) {
        final context = _stepKeys[steps[i]]?.currentContext;
        if (context == null) continue; // not in the tree — skip to the next
        Scrollable.ensureVisible(
          context,
          duration: _scrollDuration,
          curve: _scrollCurve,
          alignment: i == steps.length - 1 ? _submitAlignment : _questionAlignment,
        );
        return;
      }
    });
  }
}
