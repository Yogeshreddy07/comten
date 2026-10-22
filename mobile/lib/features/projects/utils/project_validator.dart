import '../../../core/utils/validators.dart';

class ProjectValidator {
  ProjectValidator._();

  static String? projectName(String? value) {
    return Validators.requiredField(value, 'Project Name');
  }

  static String? projectCode(String? value) {
    return Validators.requiredField(value, 'Project ID');
  }

  static String? existingProject(int? projectId) {
    if (projectId == null) {
      return 'Project is required';
    }
    return null;
  }
}
