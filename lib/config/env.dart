class Env {
  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  // Public client-side DSN; baked in as default so CI builds get it without
  // extra secrets. Override with --dart-define=SENTRY_DSN=... if needed.
  static const sentryDsn = String.fromEnvironment(
    'SENTRY_DSN',
    defaultValue:
        'https://7a03dbb78f31a3e898b74595c0a69782@o4511773075177472.ingest.us.sentry.io/4511773088940034',
  );
}
