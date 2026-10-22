/// The predefined set of Single Points of Contact selectable on the Update
/// Billing Status screen - mirrors the backend's `com.comten.enums.SpocName`
/// exactly (values sent/received as these upper-snake-case names).
enum SpocName {
  prabhakaran,
  shanmugasundaram,
  hariharasudhan,
}

extension SpocNameX on SpocName {
  String get label {
    switch (this) {
      case SpocName.prabhakaran:
        return 'Prabhakaran';
      case SpocName.shanmugasundaram:
        return 'Shanmugasundaram';
      case SpocName.hariharasudhan:
        return 'Hariharasudhan';
    }
  }

  String get apiValue {
    switch (this) {
      case SpocName.prabhakaran:
        return 'PRABHAKARAN';
      case SpocName.shanmugasundaram:
        return 'SHANMUGASUNDARAM';
      case SpocName.hariharasudhan:
        return 'HARIHARASUDHAN';
    }
  }

  static SpocName? fromApiValue(String? value) {
    switch (value?.trim().toUpperCase()) {
      case 'PRABHAKARAN':
        return SpocName.prabhakaran;
      case 'SHANMUGASUNDARAM':
        return SpocName.shanmugasundaram;
      case 'HARIHARASUDHAN':
        return SpocName.hariharasudhan;
      default:
        return null;
    }
  }
}
