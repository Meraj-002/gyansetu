/// No writable audio directory on this platform (the web).
///
/// Callers treat null as "saving is not possible here" and say so, rather than
/// reporting a save that never happened.
Future<String?> resolveAudioDirectory() async => null;
