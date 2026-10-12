import 'package:flutter/material.dart';

import 'db_service.dart';

class AuthState extends ChangeNotifier {
  String? _role;
  String? get role => _role;

  bool get isLoggedIn => _role != null;

  void restore(String? role) {
    _role = role;
  }

  void login(String role) {
    _role = role;
    notifyListeners();
  }

  Future<void> logout() async {
    await DBService.clearAuthSession();
    _role = null;
    notifyListeners();
  }
}
