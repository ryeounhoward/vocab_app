import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ExamCountdownPage extends StatefulWidget {
  const ExamCountdownPage({super.key});

  @override
  State<ExamCountdownPage> createState() => _ExamCountdownPageState();
}

class _ExamCountdownPageState extends State<ExamCountdownPage> {
  static const String _defaultNoteText =
      'Stay focused, stay prepared, and keep pushing forward!';
  DateTime _selectedDate = DateTime(2026, 3, 8);
  bool _showInMenu = true;
  bool _showNote = true;
  List<String> _notes = [_defaultNoteText];
  int _noteDurationSeconds = 4;
  bool _isSaving = false;
  Duration _timeLeft = Duration.zero;
  Timer? _countdownTimer;
  String _paletteId = 'indigo';
  bool _pauseCountdown = false;
  final FocusNode _paletteFocusNode = FocusNode();

  static final List<_CountdownPalette> _palettes = [
    _CountdownPalette(
      id: 'indigo',
      name: 'Indigo (Default)',
      light: Colors.indigo.shade50,
      dark: Colors.indigo,
    ),
    _CountdownPalette(
      id: 'teal',
      name: 'Teal',
      light: Colors.teal.shade100,
      dark: Colors.teal.shade600,
    ),
    _CountdownPalette(
      id: 'emerald',
      name: 'Emerald',
      light: Colors.green.shade100,
      dark: Colors.green.shade600,
    ),
    _CountdownPalette(
      id: 'blue',
      name: 'Blue',
      light: Colors.blue.shade100,
      dark: Colors.blue.shade600,
    ),
    _CountdownPalette(
      id: 'cyan',
      name: 'Cyan',
      light: Colors.cyan.shade100,
      dark: Colors.cyan.shade700,
    ),
    _CountdownPalette(
      id: 'orange',
      name: 'Orange',
      light: Colors.orange.shade100,
      dark: Colors.orange.shade700,
    ),
    _CountdownPalette(
      id: 'amber',
      name: 'Amber',
      light: Colors.amber.shade100,
      dark: Colors.amber.shade700,
    ),
    _CountdownPalette(
      id: 'rose',
      name: 'Rose',
      light: Colors.pink.shade100,
      dark: Colors.pink.shade600,
    ),
    _CountdownPalette(
      id: 'purple',
      name: 'Purple',
      light: Colors.deepPurple.shade100,
      dark: Colors.deepPurple.shade600,
    ),
    _CountdownPalette(
      id: 'slate',
      name: 'Slate',
      light: Colors.blueGrey.shade100,
      dark: Colors.blueGrey.shade700,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _startCountdown();
    _paletteFocusNode.addListener(_handlePaletteFocus);
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final millis = prefs.getInt('exam_countdown_date');
    final show = prefs.getBool('exam_countdown_show') ?? true;
    final paletteId = prefs.getString('exam_countdown_palette') ?? 'indigo';
    final notesRaw = prefs.getString('exam_countdown_notes');
    final duration = prefs.getInt('exam_countdown_note_duration') ?? 4;
    final showNote = prefs.getBool('exam_countdown_note_show') ?? true;
    final decodedNotes = _decodeNotes(notesRaw);
    setState(() {
      _selectedDate = millis != null
          ? DateTime.fromMillisecondsSinceEpoch(millis)
          : DateTime(2026, 3, 8);
      _showInMenu = show;
      _showNote = showNote;
      _notes = decodedNotes.isNotEmpty ? decodedNotes : [_defaultNoteText];
      _noteDurationSeconds = _clampDuration(duration);
      _paletteId = _palettes.any((p) => p.id == paletteId)
          ? paletteId
          : 'indigo';
    });
    _startCountdown();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime(2100, 12, 31),
    );
    if (picked == null) return;
    setState(() => _selectedDate = picked);
    _startCountdown();
  }

  void _startCountdown() {
    _countdownTimer?.cancel();
    _updateCountdown();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (_pauseCountdown) return;
      _updateCountdown();
    });
  }

  void _updateCountdown() {
    final diff = _selectedDate.difference(DateTime.now());
    if (!mounted) return;
    setState(() => _timeLeft = diff.isNegative ? Duration.zero : diff);
  }

  void _handlePaletteFocus() {
    if (!mounted) return;
    final hasFocus = _paletteFocusNode.hasFocus;
    setState(() => _pauseCountdown = hasFocus);
    if (!hasFocus) {
      _updateCountdown();
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _paletteFocusNode.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'exam_countdown_date',
      _selectedDate.millisecondsSinceEpoch,
    );
    await prefs.setBool('exam_countdown_show', _showInMenu);
    await prefs.setString('exam_countdown_palette', _paletteId);
    await prefs.setString('exam_countdown_notes', jsonEncode(_notes));
    await prefs.setInt('exam_countdown_note_duration', _noteDurationSeconds);
    await prefs.setBool('exam_countdown_note_show', _showNote);
    if (!mounted) return;
    setState(() => _isSaving = false);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Exam countdown saved')));
    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final int days = _timeLeft.inDays;
    final int hours = _timeLeft.inHours % 24;
    final int minutes = _timeLeft.inMinutes % 60;
    final int seconds = _timeLeft.inSeconds % 60;

    final dateText =
        '${_selectedDate.year}-${_selectedDate.month.toString().padLeft(2, '0')}-${_selectedDate.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(title: const Text('Exam Countdown'), centerTitle: true),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildCountdownSection(days, hours, minutes, seconds),
              const SizedBox(height: 20),
              const Text(
                'Select exam date',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        dateText,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _pickDate,
                    child: const Text('Pick Date'),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show countdown'),
                value: _showInMenu,
                onChanged: (value) => setState(() => _showInMenu = value),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Show note'),
                value: _showNote,
                onChanged: (value) => setState(() => _showNote = value),
              ),
              const SizedBox(height: 8),
              Text(
                'Notes (${_notes.length})',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Manage notes'),
                subtitle: const Text('Add, edit, or remove notes'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _openNotesModal,
              ),
              const SizedBox(height: 8),
              if (_notes.length > 1) ...[
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Note display duration',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Text('${_noteDurationSeconds}s'),
                  ],
                ),
                Slider(
                  value: _noteDurationSeconds.toDouble(),
                  min: 2,
                  max: 10,
                  divisions: 8,
                  label: '${_noteDurationSeconds}s',
                  onChanged: (value) =>
                      setState(() => _noteDurationSeconds = value.round()),
                ),
                const SizedBox(height: 8),
              ],
              const Text(
                'Countdown colors',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Theme(
                data: Theme.of(context).copyWith(
                  textSelectionTheme: const TextSelectionThemeData(
                    cursorColor: Colors.transparent,
                    selectionColor: Colors.transparent,
                    selectionHandleColor: Colors.transparent,
                  ),
                ),
                child: DropdownMenu<String>(
                  width: MediaQuery.of(context).size.width - 32,
                  menuHeight: 320,
                  initialSelection: _paletteId,
                  label: const Text('Countdown Colors'),
                  focusNode: _paletteFocusNode,
                  onSelected: (value) {
                    if (value == null) return;
                    setState(() => _paletteId = value);
                  },
                  dropdownMenuEntries: _palettes
                      .map(
                        (p) => DropdownMenuEntry<String>(
                          value: p.id,
                          label: p.name,
                          labelWidget: Row(
                            children: [
                              _ColorSquare(color: p.light),
                              const SizedBox(width: 6),
                              _ColorSquare(color: p.dark),
                              const SizedBox(width: 10),
                              Text(p.name),
                            ],
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Wrap(
          runSpacing: 20,
          children: [
            SizedBox(
              height: 55,
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                onPressed: _isSaving ? null : _save,
                child: _isSaving
                    ? const CircularProgressIndicator(color: Colors.white)
                    : const Text(
                        'SAVE CHANGES',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildCountdownSection(int d, int h, int m, int s) {
    final palette = _palettes.firstWhere(
      (p) => p.id == _paletteId,
      orElse: () => _palettes.first,
    );
    final cardColor = palette.light;
    final titleColor = _useLightText(cardColor) ? Colors.white : Colors.black87;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Exam Countdown',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: titleColor,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildCountdownBox('$d', 'Days'),
              const SizedBox(width: 8),
              _buildCountdownBox('$h', 'Hours'),
              const SizedBox(width: 8),
              _buildCountdownBox('$m', 'Mins'),
              const SizedBox(width: 8),
              _buildCountdownBox('$s', 'Secs'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCountdownBox(String value, String label) {
    final palette = _palettes.firstWhere(
      (p) => p.id == _paletteId,
      orElse: () => _palettes.first,
    );
    final badgeColor = palette.dark;
    final forceWhite = palette.id == 'orange';
    final valueColor = forceWhite
        ? Colors.white
        : _useLightText(badgeColor)
        ? Colors.white
        : Colors.black87;
    final labelColor = forceWhite
        ? Colors.white70
        : valueColor.withOpacity(0.7);
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: badgeColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: valueColor,
              ),
            ),
            Text(label, style: TextStyle(fontSize: 10, color: labelColor)),
          ],
        ),
      ),
    );
  }

  bool _useLightText(Color color) {
    return ThemeData.estimateBrightnessForColor(color) == Brightness.dark;
  }

  int _clampDuration(int value) {
    if (value < 2) return 2;
    if (value > 10) return 10;
    return value;
  }

  List<String> _decodeNotes(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        return decoded
            .whereType<String>()
            .map((note) => note.trim())
            .where((note) => note.isNotEmpty)
            .toList();
      }
    } catch (_) {
      return [];
    }
    return [];
  }

  Future<void> _openNotesModal() async {
    if (!mounted) return;
    final updated = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final notes = List<String>.from(_notes);
        const int pageSize = 5;
        int currentPage = 0;
        return StatefulBuilder(
          builder: (context, setModalState) {
            Future<void> addOrEdit({String? initial, int? index}) async {
              final controller = TextEditingController(text: initial ?? '');
              final result = await showDialog<String>(
                context: context,
                builder: (context) {
                  final dialogWidth = MediaQuery.of(context).size.width - 32;
                  return AlertDialog(
                    insetPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 24,
                    ),
                    title: Text(index == null ? 'Add note' : 'Edit note'),
                    content: SizedBox(
                      width: dialogWidth,
                      child: TextField(
                        controller: controller,
                        minLines: 4,
                        maxLines: null,
                        maxLength: 100,
                        keyboardType: TextInputType.multiline,
                        textAlignVertical: TextAlignVertical.top,
                        scrollPhysics: const NeverScrollableScrollPhysics(),
                        decoration: const InputDecoration(
                          hintText: 'Enter note',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: controller,
                        builder: (context, value, child) {
                          final canSave = value.text.trim().isNotEmpty;
                          return ElevatedButton(
                            onPressed: canSave
                                ? () =>
                                      Navigator.pop(context, value.text.trim())
                                : null,
                            child: const Text('Save'),
                          );
                        },
                      ),
                    ],
                  );
                },
              );
              if (result == null || result.isEmpty) return;
              setModalState(() {
                if (index == null) {
                  notes.add(result);
                } else {
                  notes[index] = result;
                }
              });
            }

            int totalPages() {
              if (notes.isEmpty) return 1;
              return ((notes.length - 1) ~/ pageSize) + 1;
            }

            void movePage(int page) {
              if (notes.isEmpty) {
                currentPage = 0;
              } else {
                currentPage = page.clamp(0, totalPages() - 1);
              }
            }

            return SafeArea(
              child: SizedBox(
                width: double.infinity,
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    16 + MediaQuery.of(context).padding.top,
                    16,
                    16 + MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Notes',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          IconButton(
                            onPressed: () => addOrEdit(),
                            icon: const Icon(Icons.add),
                            tooltip: 'Add note',
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      if (notes.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 12),
                          child: Text('No notes yet. Add your first one.'),
                        )
                      else
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Page ${currentPage + 1} of ${totalPages()}',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...List.generate(
                              (notes.length - currentPage * pageSize).clamp(
                                0,
                                pageSize,
                              ),
                              (index) {
                                final noteIndex =
                                    currentPage * pageSize + index;
                                final note = notes[noteIndex];
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: Colors.grey.shade100,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
                                    ),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: Text(note)),
                                        IconButton(
                                          onPressed: () => addOrEdit(
                                            initial: note,
                                            index: noteIndex,
                                          ),
                                          icon: const Icon(Icons.edit_outlined),
                                          tooltip: 'Edit',
                                        ),
                                        IconButton(
                                          onPressed: () => setModalState(() {
                                            notes.removeAt(noteIndex);
                                            movePage(currentPage);
                                          }),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                          tooltip: 'Delete',
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            Row(
                              children: [
                                TextButton.icon(
                                  onPressed:
                                      totalPages() <= 1 || currentPage == 0
                                      ? null
                                      : () => setModalState(() {
                                          movePage(currentPage - 1);
                                        }),
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('Prev'),
                                ),
                                const SizedBox(width: 8),
                                TextButton.icon(
                                  onPressed:
                                      totalPages() <= 1 ||
                                          currentPage >= totalPages() - 1
                                      ? null
                                      : () => setModalState(() {
                                          movePage(currentPage + 1);
                                        }),
                                  icon: const Icon(Icons.chevron_right),
                                  label: const Text('Next'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final cleaned = notes
                                    .map((note) => note.trim())
                                    .where((note) => note.isNotEmpty)
                                    .toList();
                                Navigator.pop(
                                  context,
                                  cleaned.isEmpty
                                      ? <String>[_defaultNoteText]
                                      : cleaned,
                                );
                              },
                              child: const Text('Save'),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    if (!mounted || updated == null) return;
    setState(() => _notes = updated);
  }
}

class _CountdownPalette {
  final String id;
  final String name;
  final Color light;
  final Color dark;

  const _CountdownPalette({
    required this.id,
    required this.name,
    required this.light,
    required this.dark,
  });
}

class _ColorSquare extends StatelessWidget {
  final Color color;

  const _ColorSquare({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: Colors.black12),
      ),
    );
  }
}
