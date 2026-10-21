/// Represents an individual's self-learning vocal pitch (F0) and tonal adaptation profile.
class SpeakerTonalProfile {
  final String profileId;
  final String displayName;
  final String languageCode;
  final String dialectRegion;
  final double f0MeanHz;
  final double highToneOffsetSemitones;
  final double midToneOffsetSemitones;
  final double lowToneOffsetSemitones;
  final int learnedMinimalPairsCount;
  final double adaptationConfidence;
  final bool communityFlywheelOptIn;
  final bool myVoiceConsentEnabled;

  const SpeakerTonalProfile({
    required this.profileId,
    required this.displayName,
    required this.languageCode,
    required this.dialectRegion,
    required this.f0MeanHz,
    this.highToneOffsetSemitones = 2.8,
    this.midToneOffsetSemitones = 0.0,
    this.lowToneOffsetSemitones = -3.3,
    required this.learnedMinimalPairsCount,
    required this.adaptationConfidence,
    this.communityFlywheelOptIn = true,
    this.myVoiceConsentEnabled = true,
  });

  SpeakerTonalProfile copyWith({
    double? f0MeanHz,
    int? learnedMinimalPairsCount,
    double? adaptationConfidence,
    bool? communityFlywheelOptIn,
    bool? myVoiceConsentEnabled,
  }) {
    return SpeakerTonalProfile(
      profileId: profileId,
      displayName: displayName,
      languageCode: languageCode,
      dialectRegion: dialectRegion,
      f0MeanHz: f0MeanHz ?? this.f0MeanHz,
      highToneOffsetSemitones: highToneOffsetSemitones,
      midToneOffsetSemitones: midToneOffsetSemitones,
      lowToneOffsetSemitones: lowToneOffsetSemitones,
      learnedMinimalPairsCount:
          learnedMinimalPairsCount ?? this.learnedMinimalPairsCount,
      adaptationConfidence: adaptationConfidence ?? this.adaptationConfidence,
      communityFlywheelOptIn:
          communityFlywheelOptIn ?? this.communityFlywheelOptIn,
      myVoiceConsentEnabled:
          myVoiceConsentEnabled ?? this.myVoiceConsentEnabled,
    );
  }
}

/// Represents a tonal minimal pair item for the Self-Learning Tonal Coach & Disambiguator.
class TonalMinimalPairItem {
  final String undiacritizedBase;
  final String diacritizedWord;
  final String tonePatternLabel;
  final String englishMeaning;
  final List<double> targetSemitoneCurve;
  final List<double> learnerSemitoneCurve;
  final String coachingTip;

  const TonalMinimalPairItem({
    required this.undiacritizedBase,
    required this.diacritizedWord,
    required this.tonePatternLabel,
    required this.englishMeaning,
    required this.targetSemitoneCurve,
    required this.learnerSemitoneCurve,
    required this.coachingTip,
  });
}

/// Represents a phrase saved from a translated call into ConFriKa Learn.
class SavedCallPhrase {
  final String originalPhrase;
  final String translatedPhrase;
  final String languagePair;
  final String tonalHint;

  const SavedCallPhrase({
    required this.originalPhrase,
    required this.translatedPhrase,
    required this.languagePair,
    required this.tonalHint,
  });
}
