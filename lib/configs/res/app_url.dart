class AppUrl {
  static const String baseUrl = 'http://108.136.142.112:90';

  static const String token = '$baseUrl/token';
  static const String register = '$baseUrl/register';
  static const String files = '$baseUrl/get';
  static const String upload = '$baseUrl/upload';
  static const String delete = '$baseUrl/delete';

  static String fileUrl(String name) => _withFile(files, name);
  static String deleteFileUrl(String name) => _withFile(delete, name);

  static String _withFile(String url, String name) =>
      Uri.parse(url).replace(queryParameters: {'file': name}).toString();
}
