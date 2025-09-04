import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class HelpFaqPage extends StatefulWidget {
  const HelpFaqPage({super.key});

  @override
  State<HelpFaqPage> createState() => _HelpFaqPageState();
}

class _HelpFaqPageState extends State<HelpFaqPage> {
  final List<Map<String, String>> faqs = const [
    {
      'question': 'How do I create a group?',
      'answer': 'Go to the Groups tab, click "Create Group", enter group name and select members to create a new group.'
    },
    {
      'question': 'How do I add an expense?',
      'answer': 'Open a group, click the "+" button, fill in expense details, and save. You can split it equally or customize shares.'
    },
    {
      'question': 'How do I split expenses?',
      'answer': 'When adding an expense, choose how you want to split: equally or manually select percentages for each member.'
    },
    {
      'question': 'Can I share the app with friends?',
      'answer': 'Yes! You can invite friends to a group using a join link if they are not already on the app.'
    },
    {
      'question': 'How can I track my balances?',
      'answer': 'Go to the group details page to see each member\'s balance and your overall owed/owing summary.'
    },
    {
      'question': 'How do I change my profile info?',
      'answer': 'Go to Settings > Profile > Edit Profile to update your name, email, or profile picture.'
    },
  ];

  String searchQuery = "";

  Future<void> submitSupportRequest(String message) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      // Fetch user details from Firestore
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final username = doc['fullName'] ?? 'User';
      final email = user.email ?? '';

      await FirebaseFirestore.instance.collection('support_requests').add({
        'userId': user.uid,
        'username': username,
        'email': email,
        'message': message,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      print('Error submitting support request: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredFaqs = faqs
        .where((faq) =>
        faq['question']!.toLowerCase().contains(searchQuery.toLowerCase()))
        .toList();

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Help & FAQ', style: TextStyle(color: Colors.white)),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                hintText: 'Search FAQs...',
                hintStyle: const TextStyle(color: Colors.white54),
                prefixIcon: const Icon(Icons.search, color: Colors.amberAccent),
                filled: true,
                fillColor: Colors.grey[900],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
              onChanged: (value) {
                setState(() {
                  searchQuery = value;
                });
              },
            ),
          ),

          // FAQ List
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: filteredFaqs.length,
              itemBuilder: (context, index) {
                final faq = filteredFaqs[index];
                return Card(
                  color: Colors.grey[900],
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ExpansionTile(
                    iconColor: Colors.amberAccent,
                    collapsedIconColor: Colors.amberAccent,
                    title: Text(
                      faq['question']!,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(
                          faq['answer']!,
                          style: const TextStyle(color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),

          // Submit Support Request Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12),
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.amberAccent,
                foregroundColor: Colors.black,
                minimumSize: const Size.fromHeight(50),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.support_agent),
              label: const Text(
                'Submit a Support Request',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) {
                    final TextEditingController _controller =
                    TextEditingController();
                    return AlertDialog(
                      backgroundColor: Colors.grey[900],
                      title: const Text('Support Request',
                          style: TextStyle(color: Colors.white)),
                      content: TextField(
                        controller: _controller,
                        maxLines: 5,
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          hintText: 'Describe your issue...',
                          hintStyle: TextStyle(color: Colors.white54),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancel',
                              style: TextStyle(color: Colors.amberAccent)),
                        ),
                        TextButton(
                          onPressed: () async {
                            final message = _controller.text.trim();
                            if (message.isNotEmpty) {
                              try {
                                await submitSupportRequest(message);
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Support request submitted!'),
                                    backgroundColor: Colors.amberAccent,
                                  ),
                                );
                              } catch (e) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Failed to submit request.'),
                                    backgroundColor: Colors.redAccent,
                                  ),
                                );
                              }
                            }
                          },
                          child: const Text('Submit',
                              style: TextStyle(color: Colors.amberAccent)),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
