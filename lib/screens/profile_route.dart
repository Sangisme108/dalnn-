import 'package:flutter/widgets.dart';

import 'customer_profile_screen.dart';
import 'profile_view_screen.dart';

Widget buildProfileScreenForRole(String role) {
  if (role == 'customer') {
    return const CustomerProfileScreen();
  }

  return ProfileViewScreen(role: role);
}
