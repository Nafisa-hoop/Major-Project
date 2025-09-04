import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:splitnow/screens/FeedbackPage.dart';
import 'package:splitnow/screens/HelpFaqPage.dart';
import 'package:splitnow/screens/forgot_password_page.dart';
import 'package:splitnow/screens/login_page.dart';
import 'package:splitnow/screens/profile_page.dart';
import 'package:splitnow/screens/theme_provider.dart';

import '../main.dart';
import 'EditProfilePage.dart';
import 'LanguagePage.dart';
import 'notifications_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  String username = "User";
  String email = "";
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUserInfo();
  }

  Future<void> fetchUserInfo() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        setState(() {
          username = doc['fullName'] ?? 'User';
          email = user.email ?? '';
          isLoading = false;
        });
      }
    } catch (e) {
      print("Error fetching user info: $e");
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(
          child: CircularProgressIndicator(color: Colors.amber),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          "Settings",
          style: TextStyle(color: Colors.white),
        ),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[900],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 30,
                    backgroundColor: Colors.grey,
                    child: Icon(Icons.person, color: Colors.white, size: 30),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          email,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.amber),
                    onPressed: () async {
                      // Navigate to EditProfilePage
                      final updated = await Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (context) => const EditProfilePage()));

                      // Refresh data if profile was updated
                      if (updated == true) {
                        fetchUserInfo(); // Fetch updated name/email from Firestore
                      }
                    },
                  )
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Account Section
            _buildSectionCard(
              title: "Account",
              children: [
                _buildListTile(Icons.person, "Profile", Colors.amberAccent, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const ProfilePage()),
                  );
                }),
                _buildListTile(Icons.lock, "Change Password", Colors.redAccent,
                        () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(builder: (context) => const ForgotPasswordPage()),
                          );
                    }),
              ],
            ),
            const SizedBox(height: 16),

            // Preferences Section
            _buildSectionCard(
              title: "Preferences",
              children: [
                _buildSwitchTile(
                  icon: Icons.dark_mode,
                  title: "Dark Mode",
                  iconColor: Colors.amberAccent,
                  value: Provider.of<ThemeProvider>(context).isDarkMode, // 👈 read state
                  onChanged: (val) {
                    Provider.of<ThemeProvider>(context, listen: false).toggleTheme(val); // 👈 update
                  },
                ),
                _buildListTile(
                  Icons.notifications,
                  "Notifications",
                  Colors.lightBlue,
                      () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const NotificationsPage()),
                    );
                  },
                ),
                _buildListTile(
                  Icons.language,
                  "Language",
                  Colors.greenAccent,
                      () async {
                    final newLocale = await Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const LanguagePage()),
                    );
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Support Section
            _buildSectionCard(
              title: "Support",
              children: [
                _buildListTile(
                    Icons.help, "Help & FAQ", Colors.lightBlueAccent, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HelpFaqPage()),
                  );
                }),
                _buildListTile(
                    Icons.feedback, "Send Feedback", Colors.purpleAccent, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const FeedbackPage()),
                  );
                }),
              ],
            ),
            const SizedBox(height: 16),

            // Logout
            _buildSectionCard(
              title: "",
              children: [
                _buildListTile(Icons.logout, "Logout", Colors.redAccent, () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const LoginPage()),
                  );
                  // Handle logout
                }),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard(
      {required String title, required List<Widget> children}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          if (title.isNotEmpty)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  title,
                  style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 14,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildListTile(
      IconData icon, String title, Color iconColor, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: const Icon(Icons.arrow_forward_ios,
          color: Colors.white24, size: 16),
      onTap: onTap,
    );
  }

  Widget _buildSwitchTile(
      {required IconData icon,
        required String title,
        required Color iconColor,
        required bool value,
        required ValueChanged<bool> onChanged}) {
    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(title, style: const TextStyle(color: Colors.white)),
      trailing: Switch(
        value: value,
        activeColor: Colors.amberAccent,
        onChanged: onChanged,
      ),
    );
  }
}
