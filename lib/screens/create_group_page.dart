import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

class CreateGroupPage extends StatefulWidget {
  const CreateGroupPage({super.key});

  @override
  State<CreateGroupPage> createState() => _CreateGroupPageState();
}

class _CreateGroupPageState extends State<CreateGroupPage> {
  final _groupNameController = TextEditingController();
  String? selectedExpenseType;
  DateTime? startDate;
  DateTime? endDate;

  Future<void> _pickDate(BuildContext context, bool isStart) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 2),
    );
    if (picked != null) {
      setState(() {
        if (isStart) {
          startDate = picked;
        } else {
          endDate = picked;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title:
            const Text('Create Group', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Group Name", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 8),
            TextField(
              controller: _groupNameController,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.grey[900],
                hintText: "Enter group name",
                hintStyle: const TextStyle(color: Colors.white38),
                border:
                    OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(height: 24),
            const Text("Expense Type", style: TextStyle(color: Colors.white70)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              children: ["Trip", "Home", "Bills", "Medical"].map((type) {
                final isSelected = selectedExpenseType == type;
                return ChoiceChip(
                  label:
                      Text(type, style: const TextStyle(color: Colors.white)),
                  selected: isSelected,
                  selectedColor: Colors.amber,
                  backgroundColor: Colors.grey[800],
                  onSelected: (_) {
                    setState(() {
                      selectedExpenseType = type;
                    });
                  },
                );
              }).toList(),
            ),
            const SizedBox(height: 24),
            if (selectedExpenseType == "Trip") ...[
              const Text("Trip Dates", style: TextStyle(color: Colors.white70)),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _pickDate(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[850],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        startDate != null
                            ? "Start: ${startDate!.toLocal().toString().split(' ')[0]}"
                            : "Start Date",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _pickDate(context, false),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey[850],
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: Text(
                        endDate != null
                            ? "End: ${endDate!.toLocal().toString().split(' ')[0]}"
                            : "End Date",
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 32),
            Center(
              child: ElevatedButton(
    onPressed: () async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final groupName = _groupNameController.text.trim();
    if (uid == null || groupName.isEmpty) return;

    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();

    if (!userDoc.exists) return;

    final userData = userDoc.data()!;

    // Create group first
    final groupRef = await FirebaseFirestore.instance.collection('groups').add({
    'name': groupName,
    'createdBy': uid,
    'members': [uid], // keep array of uids for easy querying
    'type': selectedExpenseType,
    'startDate': startDate != null ? Timestamp.fromDate(startDate!) : null,
    'endDate': endDate != null ? Timestamp.fromDate(endDate!) : null,
    'createdAt': FieldValue.serverTimestamp(),
    });

    // Add user to members subcollection
    await groupRef.collection('members').doc(uid).set({
    'uid': uid,
    'name': userData['fullName'] ?? '',
    'email': userData['email'] ?? '',
    'phone': userData['phone'] ?? '',
    'username': userData['username'] ?? '',
    'addedAt': FieldValue.serverTimestamp(),
    });

    Navigator.pop(context);
    },
    style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 48, vertical: 14),
                ),
                child: const Text("Create Group",
                    style: TextStyle(color: Colors.black)),
              ),
            )
          ],
        ),
      ),
    );
  }
}
