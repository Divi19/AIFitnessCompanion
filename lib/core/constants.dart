class AppConstants {
  // Injected at build/run time via --dart-define-from-file=.env
  // The actual value comes from your local .env file — never hardcoded here.
  // If this is empty string at runtime, you forgot --dart-define-from-file=.env
  static const geminiApiKey = String.fromEnvironment('GEMINI_API_KEY');

  // Safety check you can call during app startup to catch missing keys early
  static void assertKeysLoaded() {
    assert(
      geminiApiKey.isNotEmpty,
      'GEMINI_API_KEY is not set. '
      'Run with: flutter run --dart-define-from-file=.env',
    );
  }
}