/// استثناء موحّد برسالة عربية جاهزة للعرض للمستخدم.
class AppException implements Exception {
  const AppException(this.message);

  final String message;

  @override
  String toString() => message;
}
