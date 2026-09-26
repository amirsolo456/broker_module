import 'dart:io';

class AppConstants {
  static String get defaultBaseHost => Platform.isAndroid ? "http://10.0.2.2:5050" : "http://localhost:5050";
}
