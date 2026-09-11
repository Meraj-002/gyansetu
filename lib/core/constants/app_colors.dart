import 'package:flutter/material.dart';

/// Brand colour tokens for GyanSetu AI.
///
/// Visual identity: deep navy / indigo, warm saffron / gold, cream / off-white.
///
/// Screens must never hard-code a [Color]. Read colours from
/// `Theme.of(context).colorScheme` wherever a semantic role exists, and fall
/// back to these tokens only for brand-specific accents that the Material
/// [ColorScheme] has no slot for.
abstract final class AppColors {
  // --- Primary: deep navy / indigo -----------------------------------------
  static const Color primary = Color(0xFF1B2A6B);
  static const Color primaryDark = Color(0xFF101B47);
  static const Color primaryLight = Color(0xFF3D4E96);
  static const Color onPrimary = Color(0xFFFFFFFF);
  static const Color primaryContainer = Color(0xFFDDE2F5);
  static const Color onPrimaryContainer = Color(0xFF0B1338);

  // --- Secondary: warm saffron / gold --------------------------------------
  static const Color secondary = Color(0xFFE9A227);
  static const Color secondaryDark = Color(0xFFC07E12);
  static const Color secondaryLight = Color(0xFFF7C765);

  /// Deliberately near-black rather than white: white text on saffron falls
  /// below the WCAG AA contrast floor.
  static const Color onSecondary = Color(0xFF2A1D00);
  static const Color secondaryContainer = Color(0xFFFDEFD2);
  static const Color onSecondaryContainer = Color(0xFF3D2B00);

  // --- Neutrals: cream / off-white ------------------------------------------
  static const Color background = Color(0xFFFBF7EF);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceVariant = Color(0xFFF3EDE1);
  static const Color outline = Color(0xFFDCD3C3);
  static const Color outlineVariant = Color(0xFFEDE6DA);

  // --- Text ------------------------------------------------------------------
  static const Color textPrimary = Color(0xFF1A1D26);
  static const Color textSecondary = Color(0xFF5A6072);
  static const Color textDisabled = Color(0xFF9AA0AE);
  static const Color textOnDark = Color(0xFFF7F4EE);

  // --- Semantic ---------------------------------------------------------------
  static const Color success = Color(0xFF2E7D5B);
  static const Color warning = Color(0xFFC77B12);
  static const Color error = Color(0xFFB3261E);
  static const Color info = Color(0xFF2B5C9B);

  // --- Brand artwork palette ---------------------------------------------------
  // Sampled from the GyanSetu AI key art. These are the exact values the
  // illustrations are drawn in, so screens that sit next to that artwork match
  // it rather than approximating it. Kept here, with every other colour, so no
  // screen ever declares a Color of its own.
  static const Color brandNavy = Color(0xFF13305F);
  static const Color brandNavyPanel = Color(0xFF1B2F62);
  static const Color brandNavyDeep = Color(0xFF152A57);
  static const Color brandOrange = Color(0xFFEE7A22);
  static const Color brandOrangeBright = Color(0xFFFD8D2B);
  static const Color brandGold = Color(0xFFF5A437);
  static const Color brandCtaTop = Color(0xFFFCA24E);
  static const Color brandCtaBottom = Color(0xFFF2831F);
  static const Color brandCream = Color(0xFFFDFBF7);
  static const Color brandCreamWarm = Color(0xFFFBF1E4);
  static const Color brandBody = Color(0xFF33405A);
  static const Color brandMuted = Color(0xFF6B7183);
  static const Color brandOnCta = Color(0xFF14264F);
  static const Color brandOfflineGreen = Color(0xFF1F8A5B);

  // --- Login surfaces -----------------------------------------------------------
  // Sampled from the login key art, which runs a cooler, darker navy than the
  // onboarding pages and a near-white rather than warm-cream ground.
  static const Color authNavy = Color(0xFF14224B);
  static const Color authPageTop = Color(0xFFFCFCFE);
  static const Color authPageBottom = Color(0xFFF8F6F2);
  static const Color authChip = Color(0xFFF6F6FE);
  static const Color authIconCircle = Color(0xFFEDEEF5);
  static const Color authFieldBorder = Color(0xFFE4E5EC);
  static const Color authHint = Color(0xFF9AA0B0);

  // --- Classroom setup ----------------------------------------------------------
  // Sampled from the setup key art. The primary action here is saffron rather
  // than navy, because it closes a configuration rather than opening a session.
  static const Color setupCta = Color(0xFFE6A74A);
  static const Color setupSummaryNavy = Color(0xFF15254F);
  static const Color setupSelectedCream = Color(0xFFFEF9F4);
  static const Color setupLiteracy = Color(0xFF2E7D5B);
  static const Color setupLiteracyTint = Color(0xFFF3F8F4);
  static const Color setupNumeracy = Color(0xFF2B5C9B);
  static const Color setupNumeracyTint = Color(0xFFF2F7FD);

  // --- Home dashboard -----------------------------------------------------------
  static const Color homeHeroNavy = Color(0xFF16284D);
  static const Color homePage = Color(0xFFFDFDFE);
  static const Color homeOfflineTint = Color(0xFFF3F9F1);
  static const Color homeBannerTint = Color(0xFFFAF1E6);

  /// Navigation shell. Only the selected item takes the gold accent.
  static const Color navShellNavy = Color(0xFF10234B);
  static const Color navShellActive = Color(0xFFE9A227);

  // --- Live classroom ---------------------------------------------------------
  // The one deliberately dark screen in the app. A live session runs with the
  // phone held up in a classroom, often against a window, and a dark ground
  // keeps the speaker cards and the microphone readable. Sampled from the live
  // classroom key art.
  static const Color liveBackground = Color(0xFF060A1B);
  static const Color liveSurface = Color(0xFF0C1330);
  static const Color liveCard = Color(0xFF0F1732);
  static const Color liveCardRaised = Color(0xFF162041);
  static const Color liveBorder = Color(0xFF1D2950);
  static const Color liveBar = Color(0xFF0A1128);

  /// The glow behind the microphone. Blue into violet, as in the artwork.
  static const Color liveGlowBlue = Color(0xFF2F6BF0);
  static const Color liveGlowViolet = Color(0xFF8B5CF6);
  static const Color liveGlowCyan = Color(0xFF38BDF8);

  /// Speaker identity. Gold is the teacher, blue the AI, green the pupil —
  /// the same three roles the timeline uses, so colour never has to be decoded.
  static const Color liveTeacher = Color(0xFFE8A33A);
  static const Color liveAi = Color(0xFF3E82F7);
  static const Color liveStudent = Color(0xFF34C77B);

  /// Reserved for ending a session. Nothing else on this screen is red.
  static const Color liveDanger = Color(0xFFE23C3C);

  static const Color liveTextPrimary = Color(0xFFEFF3FF);
  static const Color liveTextMuted = Color(0xFF93A0C2);

  // --- Dark theme surfaces ----------------------------------------------------
  static const Color darkBackground = Color(0xFF0E1220);
  static const Color darkSurface = Color(0xFF171C2E);
  static const Color darkSurfaceVariant = Color(0xFF222941);
  static const Color darkOutline = Color(0xFF39415C);
}
