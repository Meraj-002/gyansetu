import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../services/storage/secure_storage_service.dart';
import 'conversation_result_screen.dart' show ConversationResultArgs;
import 'models/classroom_session.dart';
import 'models/conversation_turn.dart';
import 'services/classroom_session_repository.dart';

/// The detailed session report.
///
/// PLACEHOLDER, deliberately undesigned — it will get its own pass. What it
/// does now is honour the contract: it is handed a session id, reads that exact
/// session back through [ClassroomSessionRepository], and lists every recorded
/// turn with its own measured timings. Nothing here is generated.
class SessionReportScreen extends StatefulWidget {
  const SessionReportScreen({this.sessionId, this.sessions, super.key});

  static const Key listKey = Key('session-report-list');

  final String? sessionId;
  final ClassroomSessionRepository? sessions;

  @override
  State<SessionReportScreen> createState() => _SessionReportScreenState();
}

class _SessionReportScreenState extends State<SessionReportScreen> {
  ClassroomSession? _session;
  bool _resolved = false;
  bool _loading = true;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resolved) return;
    _resolved = true;

    final Object? routeArgs = ModalRoute.of(context)?.settings.arguments;
    final String? id =
        widget.sessionId ?? ConversationResultArgs.sessionIdFrom(routeArgs);
    if (id == null) {
      setState(() => _loading = false);
      return;
    }
    _load(id);
  }

  Future<void> _load(String id) async {
    final ClassroomSessionRepository repository = widget.sessions ??
        LocalClassroomSessionRepository(PlatformSecureStorageService());
    final ClassroomSession? session = await repository.byId(id);
    if (!mounted) return;
    setState(() {
      _session = session;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ClassroomSession? session = _session;

    return Scaffold(
      backgroundColor: AppColors.homePage,
      appBar: AppBar(
        title: const Text('Session report'),
        backgroundColor: AppColors.homePage,
        foregroundColor: AppColors.brandNavy,
        elevation: 0,
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : session == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: Text(
                        "Couldn't load this classroom session.",
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.brandNavy,
                        ),
                      ),
                    ),
                  )
                : ListView(
                    key: SessionReportScreen.listKey,
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                    children: <Widget>[
                      Text(
                        session.sessionId,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: AppColors.brandNavy,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${session.totalTurns} turns  •  '
                        '${session.durationLabel} min',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.brandNavy.withValues(alpha: 0.7),
                        ),
                      ),
                      const SizedBox(height: 18),
                      for (final ConversationTurn turn in session.turns)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                '${turn.speaker.label}  •  ${turn.status.name}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.brandNavy,
                                ),
                              ),
                              if (turn.sourceText.isNotEmpty)
                                Text(
                                  turn.sourceText,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              if (turn.translatedText != null)
                                Text(
                                  turn.translatedText!,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    color: AppColors.setupNumeracy,
                                  ),
                                ),
                              if (turn.metrics != null)
                                Text(
                                  'ASR '
                                  '${turn.metrics!.asrDuration.inMilliseconds}ms'
                                  '  •  Translation '
                                  '${turn.metrics!.translationDuration.inMilliseconds}ms'
                                  '  •  Audio '
                                  '${turn.metrics!.ttsDuration.inMilliseconds}ms'
                                  '  •  Total ${turn.metrics!.totalLabel}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: AppColors.brandNavy
                                        .withValues(alpha: 0.6),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
