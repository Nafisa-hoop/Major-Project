import 'package:flutter/material.dart';

class LanguagePage extends StatefulWidget {
  const LanguagePage({super.key});

  @override
  State<LanguagePage> createState() => _LanguagePageState();
}

class _LanguagePageState extends State<LanguagePage> {
  String? _selectedLang;

  final Map<String, String> languages = {
    "en": "English",
    "hi": "Hindi",
    "ar": "Arabic",
    "fr": "French",
  };

  @override
  void initState() {
    super.initState();
  }

  /*Future<void> _loadSelectedLanguage() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _selectedLang = prefs.getString("app_language") ?? "en";
    });
  }

  Future<void> _saveLanguage(String code) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString("app_language", code);

    setState(() {
      _selectedLang = code;
    });

    // Update locale instantly
    Locale newLocale = Locale(code);
    Navigator.pop(context, newLocale);
  }
*/
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text("Select Language", style: TextStyle(color: Colors.white)),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: ListView(
        children: languages.entries.map((entry) {
          return RadioListTile<String>(
            value: entry.key,
            groupValue: _selectedLang,
            onChanged: (val) {},
            title: Text(entry.value, style: const TextStyle(color: Colors.white)),
            activeColor: Colors.amber,
          );
        }).toList(),
      ),
    );
  }
}
