/// Paths to bundled assets.
///
/// Referenced through constants so that a moved or renamed file is a single
/// edit, and so a typo cannot survive to runtime as a silent missing-asset box.
abstract final class AppAssets {
  static const String _images = 'assets/images';

  /// Full-bleed splash artwork, drawn at 852x1846 (roughly 9:19.5).
  static const String splashArtwork = '$_images/gyan_setu_splash.png';

  /// Intrinsic aspect ratio (width / height) of [splashArtwork].
  static const double splashArtworkAspectRatio = 852 / 1846;

  /// The bridge-and-learners mark, keyed to transparency so it sits on any
  /// background. The wordmark beside it is rendered as text, never baked in.
  static const String brandMark = '$_images/brand_mark.png';
  static const double brandMarkAspectRatio = 122 / 54;

  /// Onboarding page 1: the classroom scene, full width.
  static const String onboardingClassroom = '$_images/onboarding_classroom.png';
  static const double onboardingClassroomAspectRatio = 394 / 320;

  /// Onboarding page 2: the speaking teacher, cropped clear of any artwork the
  /// UI has to redraw as live widgets.
  static const String onboardingTeacher = '$_images/onboarding_teacher.png';
  static const double onboardingTeacherAspectRatio = 118 / 358;

  /// Onboarding page 2: the blurred class band that grounds the scene.
  static const String onboardingClassBlur =
      '$_images/onboarding_class_blur.png';
  static const double onboardingClassBlurAspectRatio = 391 / 68;

  /// Onboarding page 3: hands holding a device in a rural classroom. The
  /// device's screen is redrawn on top; see `OfflineShowcase.screenRect`.
  static const String onboardingOffline = '$_images/onboarding_offline.png';
  static const double onboardingOfflineAspectRatio = 431 / 268;

  /// Login masthead: the bridge mark, keyed to transparency.
  static const String loginBrandMark = '$_images/login_brand_mark.png';
  static const double loginBrandMarkAspectRatio = 192 / 133;

  /// Faint village-and-classroom band behind the welcome heading.
  static const String loginLandscape = '$_images/login_landscape.png';
  static const double loginLandscapeAspectRatio = 864 / 162;

  /// Tribal corner motif, keyed so it can be tinted and mirrored per corner.
  static const String tribalCorner = '$_images/tribal_corner.png';
  static const double tribalCornerAspectRatio = 152 / 296;

  /// Tribal motifs shown on the teaching-language cards.
  static const String motifSantali = '$_images/motif_santali.png';
  static const String motifMundari = '$_images/motif_mundari.png';
  static const String motifHo = '$_images/motif_ho.png';
  static const String motifEnglish = '$_images/motif_english.png';

  /// Avatar on the classroom summary card.
  static const String setupClassroomAvatar =
      '$_images/setup_classroom_avatar.png';

  /// Home hero: the lesson shown on a tablet, cropped on its navy ground so it
  /// sits seamlessly inside the hero card.
  static const String homeLessonTablet = '$_images/home_lesson_tablet.png';
  static const double homeLessonTabletAspectRatio = 338 / 328;

  /// Home offline card: the rural scene, on its own green tint.
  static const String homeOfflineScene = '$_images/home_offline_scene.png';
  static const double homeOfflineSceneAspectRatio = 356 / 208;
}
