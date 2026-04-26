import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/notification_service.dart';

class TimerPreset {
  final String label;
  final Duration duration;

  const TimerPreset({
    required this.label,
    required this.duration,
  });
}

typedef TimerNotificationScheduler = Future<TimerScheduleResult> Function({
  required int id,
  required String title,
  required Duration duration,
});

typedef TimerNotificationCanceller = Future<void> Function(int id);

class InlineTimerCard extends StatefulWidget {
  final String title;
  final List<TimerPreset>? presets;
  final bool showCustomDuration;
  final bool compact;
  final TimerNotificationScheduler? scheduleTimerNotification;
  final TimerNotificationCanceller? cancelTimerNotification;

  const InlineTimerCard({
    super.key,
    required this.title,
    this.presets,
    this.showCustomDuration = true,
    this.compact = false,
    this.scheduleTimerNotification,
    this.cancelTimerNotification,
  });

  @override
  State<InlineTimerCard> createState() => _InlineTimerCardState();
}

class _InlineTimerCardState extends State<InlineTimerCard> {
  Timer? _timer;
  int _remainingSeconds = 0;
  int _initialSeconds = 0;
  bool _isRunning = false;
  bool _isScheduling = false;
  int? _notificationId;
  String _selectedSound = NotificationService.selectedSound;
  String _stateLabel = 'Prêt';
  String? _statusMessage = 'Choisis une durée, puis lance le minuteur.';

  final TextEditingController _minutesController = TextEditingController();
  final TextEditingController _secondsController = TextEditingController();

  int _makeNotificationId() {
    return DateTime.now().millisecondsSinceEpoch.remainder(1000000);
  }

  Future<void> _start(int seconds, {String? statusMessage}) async {
    if (_isRunning || _isScheduling) {
      setState(() {
        _statusMessage = 'Un minuteur est déjà en cours.';
      });
      return;
    }

    if (seconds <= 0) {
      setState(() {
        _stateLabel = 'Prêt';
        _statusMessage = 'Entre une durée supérieure à zéro.';
      });
      return;
    }

    _timer?.cancel();

    if (_notificationId != null) {
      await _cancelNotification(_notificationId!);
    }

    final id = _makeNotificationId();

    setState(() {
      _isScheduling = true;
      _remainingSeconds = seconds;
      _initialSeconds = seconds;
      _notificationId = id;
      _stateLabel = 'Programmation...';
      _statusMessage = statusMessage ?? 'Programmation du minuteur...';
    });

    TimerScheduleResult result;
    try {
      result = await _scheduleNotification(
        id: id,
        title: widget.title,
        duration: Duration(seconds: seconds),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isScheduling = false;
        _remainingSeconds = 0;
        _initialSeconds = 0;
        _notificationId = null;
        _stateLabel = 'Prêt';
        _statusMessage = 'Impossible de programmer le minuteur.';
      });
      return;
    }

    if (!mounted) return;

    if (!result.scheduled) {
      setState(() {
        _isScheduling = false;
        _remainingSeconds = 0;
        _initialSeconds = 0;
        _notificationId = null;
        _stateLabel = 'Prêt';
        _statusMessage = result.message ?? 'Notifications non disponibles.';
      });
      return;
    }

    setState(() {
      _isScheduling = false;
      _isRunning = true;
      _stateLabel = 'En cours';
      _statusMessage = result.message ?? statusMessage ?? 'Minuteur lancé.';
    });

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds <= 1) {
        timer.cancel();
        setState(() {
          _remainingSeconds = 0;
          _initialSeconds = 0;
          _isRunning = false;
          _notificationId = null;
          _stateLabel = 'Terminé';
          _statusMessage = 'Minuteur terminé.';
        });

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('${widget.title} : minuteur terminé')),
          );
        }
      } else {
        setState(() {
          _remainingSeconds -= 1;
        });
      }
    });
  }

  Future<void> _startCustom() async {
    final minutes = int.tryParse(_minutesController.text.trim()) ?? 0;
    final seconds = int.tryParse(_secondsController.text.trim()) ?? 0;
    final messages = <String>[];
    final normalizedSeconds = seconds.clamp(0, 59).toInt();
    final normalizedMinutes = minutes.clamp(0, 999).toInt();

    if (seconds > 59) {
      messages.add('Secondes limitées à 59.');
    }

    if (minutes > 999) {
      messages.add('Minutes limitées à 999.');
    }

    final total = (normalizedMinutes * 60) + normalizedSeconds;

    if (total == 0) {
      setState(() {
        _stateLabel = 'Prêt';
        _statusMessage = 'Entre une durée supérieure à zéro.';
      });
      return;
    }

    await _start(
      total,
      statusMessage: messages.isEmpty ? null : messages.join(' '),
    );
  }

  Future<void> _stop() async {
    _timer?.cancel();

    if (_notificationId != null) {
      await _cancelNotification(_notificationId!);
    }

    if (!mounted) return;

    setState(() {
      _isRunning = false;
      _isScheduling = false;
      _remainingSeconds = 0;
      _initialSeconds = 0;
      _notificationId = null;
      _stateLabel = 'Arrêté';
      _statusMessage = 'Minuteur arrêté.';
    });
  }

  Future<TimerScheduleResult> _scheduleNotification({
    required int id,
    required String title,
    required Duration duration,
  }) {
    final schedule = widget.scheduleTimerNotification ??
        NotificationService.scheduleTimerNotificationWithResult;
    return schedule(id: id, title: title, duration: duration);
  }

  Future<void> _cancelNotification(int id) {
    final cancel = widget.cancelTimerNotification ??
        NotificationService.cancelNotification;
    return cancel(id);
  }

  String _formatTime(int totalSeconds) {
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }

    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Widget _presetButton(int index, String label, int seconds) {
    if (widget.compact) {
      return Padding(
        padding: const EdgeInsets.only(right: 8, bottom: 8),
        child: OutlinedButton.icon(
          onPressed: _isRunning || _isScheduling ? null : () => _start(seconds),
          icon: const Icon(Icons.play_arrow_rounded, size: 18),
          label: Text(label),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFD97706),
            side: const BorderSide(color: Color(0xFFE9DDD0)),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            textStyle: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _isRunning || _isScheduling ? null : () => _start(seconds),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF7F3EE),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE9DDD0)),
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6A6058),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F1A17),
                  ),
                ),
              ),
              const Icon(
                Icons.play_arrow_rounded,
                color: Color(0xFFD97706),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _timeField(String label, TextEditingController controller) {
    return Expanded(
      child: TextField(
        controller: controller,
        enabled: !_isRunning && !_isScheduling,
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: const Color(0xFFF7F3EE),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE9DDD0)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE9DDD0)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFD97706)),
          ),
        ),
      ),
    );
  }

  Future<void> _changeSound(String? sound) async {
    if (sound == null) return;

    await NotificationService.setSelectedSound(sound);
    if (!mounted) return;

    setState(() {
      _selectedSound = sound;
      _statusMessage = 'Sonnerie: ${NotificationService.soundLabels[sound]}';
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    if (_notificationId != null) {
      _cancelNotification(_notificationId!).catchError(
        (_) {},
      );
    }
    _minutesController.dispose();
    _secondsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final presets = widget.presets ?? const <TimerPreset>[];
    final progressValue = _isRunning && _initialSeconds > 0
        ? _remainingSeconds / _initialSeconds
        : null;

    if (widget.compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                _formatTime(_remainingSeconds),
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F1A17),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _stateLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD97706),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: _isRunning || _isScheduling ? _stop : null,
                child: const Text('Arrêter'),
              ),
            ],
          ),
          if (_isRunning && _remainingSeconds > 0)
            Padding(
              padding: const EdgeInsets.only(top: 8, bottom: 12),
              child: LinearProgressIndicator(
                value: progressValue,
                minHeight: 3,
                borderRadius: BorderRadius.circular(8),
                color: const Color(0xFFD97706),
                backgroundColor: const Color(0xFFF7F3EE),
              ),
            ),
          if (presets.isNotEmpty) const SizedBox(height: 10),
          if (presets.isNotEmpty)
            Wrap(
              children: presets
                  .asMap()
                  .entries
                  .map(
                    (entry) => _presetButton(
                      entry.key,
                      entry.value.label,
                      entry.value.duration.inSeconds,
                    ),
                  )
                  .toList(),
            ),
          if (_statusMessage != null) const SizedBox(height: 8),
          if (_statusMessage != null)
            Text(
              _statusMessage!,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF6A6058),
              ),
            ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE9DDD0)),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Minuteur',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F1A17),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(
                    Icons.notifications_active_outlined,
                    size: 18,
                    color: Color(0xFF6A6058),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _isRunning
                          ? 'Notification programmée en arrière-plan'
                          : 'Sonnerie même si l’app passe en arrière-plan',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF6A6058),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _stateLabel,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFD97706),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _formatTime(_remainingSeconds),
                style: const TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F1A17),
                ),
              ),
              const SizedBox(height: 12),
              if (_isRunning && _remainingSeconds > 0)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: LinearProgressIndicator(
                    value: progressValue,
                    minHeight: 4,
                    borderRadius: BorderRadius.circular(8),
                    color: const Color(0xFFD97706),
                    backgroundColor: const Color(0xFFF7F3EE),
                  ),
                ),
              if (presets.isNotEmpty)
                const Text(
                  'Étapes',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF6A6058),
                  ),
                ),
              if (presets.isNotEmpty) const SizedBox(height: 10),
              ...presets.asMap().entries.map(
                    (entry) => _presetButton(
                      entry.key,
                      entry.value.label,
                      entry.value.duration.inSeconds,
                    ),
                  ),
              OutlinedButton(
                onPressed: _isRunning || _isScheduling ? _stop : null,
                child: const Text('Arrêter'),
              ),
              if (widget.showCustomDuration) const SizedBox(height: 16),
              if (widget.showCustomDuration)
                DropdownButtonFormField<String>(
                  initialValue: _selectedSound,
                  decoration: InputDecoration(
                    labelText: 'Sonnerie',
                    filled: true,
                    fillColor: const Color(0xFFF7F3EE),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE9DDD0)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFE9DDD0)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: const BorderSide(color: Color(0xFFD97706)),
                    ),
                  ),
                  items: NotificationService.soundLabels.entries.map((entry) {
                    return DropdownMenuItem<String>(
                      value: entry.key,
                      child: Text(entry.value),
                    );
                  }).toList(),
                  onChanged: _isRunning || _isScheduling ? null : _changeSound,
                ),
              if (widget.showCustomDuration) const SizedBox(height: 16),
              if (widget.showCustomDuration)
                const Text(
                  'Durée personnalisée',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F1A17),
                  ),
                ),
              if (widget.showCustomDuration) const SizedBox(height: 10),
              if (widget.showCustomDuration)
                Row(
                  children: [
                    _timeField('Min', _minutesController),
                    const SizedBox(width: 10),
                    _timeField('Sec', _secondsController),
                  ],
                ),
              if (widget.showCustomDuration) const SizedBox(height: 10),
              if (widget.showCustomDuration)
                ElevatedButton(
                  onPressed: _isRunning || _isScheduling ? null : _startCustom,
                  child: Text(
                    _isScheduling ? 'Programmation...' : 'Lancer le minuteur',
                  ),
                ),
              if (_statusMessage != null) const SizedBox(height: 10),
              if (_statusMessage != null)
                Text(
                  _statusMessage!,
                  style: const TextStyle(
                    fontSize: 13,
                    color: Color(0xFF6A6058),
                  ),
                ),
            ],
          );

          if (!constraints.hasBoundedHeight) {
            return content;
          }

          return SingleChildScrollView(child: content);
        },
      ),
    );
  }
}
