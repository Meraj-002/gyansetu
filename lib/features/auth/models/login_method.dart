/// The three ways a teacher can identify themselves on the login card.
enum LoginMethod {
  mobile(label: 'Mobile Number'),
  teacherId(label: 'Teacher ID'),
  pin(label: 'PIN');

  const LoginMethod({required this.label});

  final String label;
}
