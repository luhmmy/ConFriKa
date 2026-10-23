import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/constants/african_countries.dart';
import '../../core/network/api_client.dart';
import '../../core/session.dart';
import '../../core/theme/confrika_theme.dart';

class TranslateScreen extends StatefulWidget {
  const TranslateScreen({super.key});

  @override
  State<TranslateScreen> createState() => _TranslateScreenState();
}

class _TranslateScreenState extends State<TranslateScreen> {
  final _inputController = TextEditingController();
  final _api = ConFriKaApiClient.instance;

  late final List<String> _languageOptions;
  late String _sourceLang;
  late String _targetLang;
  String _formality = 'respectful';

  Timer? _debounce;
  int _requestId = 0;
  bool _isTranslating = false;
  String _translatedText = '';
  double _confidence = 0;
  String _model = '';
  List<String> _diacritics = const [];
  String? _error;

  static const _globalLanguages = [
    'English',
    'Français (French)',
    'Português (Portuguese)',
    'العربية (Arabic)',
    'Afrikaans',
  ];

  final List<String> _quickPhrases = const [
    'Good morning, I hope you slept well?',
    'Thank you for yesterday, how is everyone?',
    'How much is this? Let us agree on a fair price.',
    'Where is the market or the tech hub?',
    'Safe travels and a peaceful journey!',
  ];

  @override
  void initState() {
    super.initState();
    _languageOptions = [..._globalLanguages, ...kAll54AfricanDialects];
    _sourceLang = 'English';
    // Default target to the language the user picked in the top-bar selector
    // (falls back to their own dialect), kept in sync as that choice changes.
    _targetLang = _resolveTarget(ConFriKaSession.instance.preferredLanguage);
    ConFriKaSession.instance.addListener(_onPreferredLanguageChanged);
  }

  /// Map a free-form language name to the closest option in the picker list.
  String _resolveTarget(String language) {
    final first = language.split(' ').first;
    return _languageOptions.firstWhere(
      (o) => o == language || o.contains(first),
      orElse: () => _languageOptions.firstWhere(
        (o) => o.contains('Yorùbá'),
        orElse: () => _languageOptions[5],
      ),
    );
  }

  void _onPreferredLanguageChanged() {
    final resolved = _resolveTarget(ConFriKaSession.instance.preferredLanguage);
    if (!mounted || resolved == _targetLang) return;
    setState(() => _targetLang = resolved);
    _translateNow();
  }

  @override
  void dispose() {
    ConFriKaSession.instance.removeListener(_onPreferredLanguageChanged);
    _debounce?.cancel();
    _inputController.dispose();
    super.dispose();
  }

  void _onTextChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _translateNow);
  }

  Future<void> _translateNow() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) {
      setState(() {
        _translatedText = '';
        _error = null;
        _model = '';
        _diacritics = const [];
      });
      return;
    }
    final reqId = ++_requestId;
    setState(() {
      _isTranslating = true;
      _error = null;
    });
    try {
      final res = await _api.translate(
        text: text,
        sourceDialect: _sourceLang,
        targetDialect: _targetLang,
        formality: _formality,
      );
      if (reqId != _requestId || !mounted) return; // a newer request superseded this
      setState(() {
        _translatedText = res['translated_text'] as String? ?? '';
        _confidence = ((res['confidence_score'] as num?) ?? 0).toDouble();
        _model = res['model'] as String? ?? '';
        _diacritics =
            ((res['detected_diacritics'] as List?) ?? const []).map((e) => '$e').toList();
        _isTranslating = false;
      });
    } on ApiException catch (e) {
      if (reqId != _requestId || !mounted) return;
      setState(() {
        _isTranslating = false;
        _error = e.statusCode == 401
            ? 'Your session expired. Please sign in again.'
            : e.message;
      });
    }
  }

  void _swap() {
    setState(() {
      final t = _sourceLang;
      _sourceLang = _targetLang;
      _targetLang = t;
      final prev = _translatedText;
      if (prev.isNotEmpty) _inputController.text = prev;
    });
    _translateNow();
  }

  @override
  Widget build(BuildContext context) {
    final unsupported = _model == 'identity' && _sourceLang != _targetLang;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Translate',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const Text('Real-time neural translation across African languages',
            style: TextStyle(fontSize: 12, color: Colors.grey)),
        const SizedBox(height: 14),

        // Language pair selectors with swap.
        Row(
          children: [
            Expanded(child: _langDropdown('FROM', _sourceLang, (v) {
              setState(() => _sourceLang = v);
              _translateNow();
            })),
            IconButton(
              tooltip: 'Swap direction',
              onPressed: _swap,
              icon: const Icon(Icons.swap_horiz, color: ConFriKaColors.oceanBlue),
            ),
            Expanded(child: _langDropdown('TO', _targetLang, (v) {
              setState(() => _targetLang = v);
              _translateNow();
            })),
          ],
        ),
        const SizedBox(height: 10),

        SegmentedButton<String>(
          segments: const [
            ButtonSegment(value: 'respectful', label: Text('Respectful')),
            ButtonSegment(value: 'formal', label: Text('Formal')),
            ButtonSegment(value: 'casual', label: Text('Casual')),
          ],
          selected: {_formality},
          onSelectionChanged: (s) {
            setState(() => _formality = s.first);
            _translateNow();
          },
        ),
        const SizedBox(height: 12),

        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: _quickPhrases
                .map((p) => Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ActionChip(
                        label: Text(p,
                            style: const TextStyle(
                                fontSize: 11, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          _inputController.text = p;
                          _translateNow();
                        },
                      ),
                    ))
                .toList(),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('SOURCE TEXT',
                        style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey)),
                    if (_inputController.text.isNotEmpty)
                      GestureDetector(
                        onTap: () {
                          _inputController.clear();
                          _translateNow();
                        },
                        child: const Text('Clear',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.redAccent,
                                fontWeight: FontWeight.bold)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _inputController,
                  maxLines: 3,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  decoration: const InputDecoration(
                    hintText: 'Type any phrase, sentence, or word...',
                    border: InputBorder.none,
                    isDense: true,
                  ),
                  onChanged: _onTextChanged,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),

        Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: ConFriKaColors.savannaGreen, width: 2),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text('TRANSLATION · ${_targetLang.toUpperCase()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: ConFriKaColors.savannaGreen)),
                    ),
                    if (_isTranslating)
                      const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                  ],
                ),
                const SizedBox(height: 10),
                if (_error != null)
                  Text(_error!, style: const TextStyle(color: Colors.redAccent, fontSize: 14))
                else if (unsupported)
                  Text(
                    'Neural translation for "$_targetLang" is not yet available in the current model. Try a major regional language (Yorùbá, Igbo, Hausa, Swahili, Zulu, Amharic, Twi…).',
                    style: const TextStyle(fontSize: 13, color: Colors.orange),
                  )
                else
                  SelectableText(
                    _translatedText.isEmpty ? '—' : _translatedText,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                if (_translatedText.isNotEmpty && !unsupported && _error == null) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: [
                      if (_confidence > 0)
                        _chip('Confidence ${(_confidence * 100).round()}%'),
                      if (_diacritics.isNotEmpty)
                        _chip('Tone marks: ${_diacritics.length}'),
                      if (_model.isNotEmpty && _model != 'identity')
                        _chip(_model.split('/').last),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _chip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: ConFriKaColors.oceanBlue.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: ConFriKaColors.oceanBlue)),
      );

  Widget _langDropdown(String label, String value, ValueChanged<String> onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.black12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey)),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isExpanded: true,
              isDense: true,
              items: _languageOptions
                  .map((o) => DropdownMenuItem(
                        value: o,
                        child: Text(o,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.bold),
                            overflow: TextOverflow.ellipsis),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }
}
