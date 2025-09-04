import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'AddExpensePage.dart';
import 'ExpenseDetailPage.dart';

class GroupDetailPage extends StatefulWidget {
  final DocumentSnapshot groupData;

  const GroupDetailPage({super.key, required this.groupData});

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  @override
  void initState() {
    super.initState();
    _ensureCurrentUserIsMember();
  }
  Future<void> _showUpdateMemberDialog(String groupId, String memberId, Map<String, dynamic> data) async {
    TextEditingController nameController = TextEditingController(text: data['name']);
    TextEditingController emailController = TextEditingController(text: data['email']);

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Update Member"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(controller: nameController, decoration: const InputDecoration(labelText: "Name")),
              TextField(controller: emailController, decoration: const InputDecoration(labelText: "Email")),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
            ElevatedButton(
              onPressed: () async {
                await FirebaseFirestore.instance
                    .collection('groups')
                    .doc(groupId)
                    .collection('members')
                    .doc(memberId)
                    .update({
                  'name': nameController.text,
                  'email': emailController.text,
                });
                Navigator.pop(context);
              },
              child: const Text("Update"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _ensureCurrentUserIsMember() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final groupId = widget.groupData.id;
    final groupRef =
    FirebaseFirestore.instance.collection('groups').doc(groupId);

    final memberQuery = await groupRef
        .collection('members')
        .where('uid', isEqualTo: user.uid)
        .get();

    if (memberQuery.docs.isEmpty) {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      final userData = userDoc.data() ?? {};

      await groupRef.collection('members').doc(user.uid).set({
        'uid': user.uid,
        'name': userData['fullName'] ??
            userData['username'] ??
            user.displayName ??
            'User',
        'email': userData['email'] ?? user.email ?? '',
        'addedAt': FieldValue.serverTimestamp(),
      });

      await groupRef.update({
        'members': FieldValue.arrayUnion([user.uid])
      });
    }
  }

  Future<void> _showAddMemberDialog(String groupId) async {
    String memberEmail = "";

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Add Member"),
          content: TextField(
            decoration: const InputDecoration(
              labelText: "Enter Member Email",
            ),
            onChanged: (value) => memberEmail = value.trim(),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () async {
                if (memberEmail.isEmpty) return;

                final userQuery = await FirebaseFirestore.instance
                    .collection('users')
                    .where('email', isEqualTo: memberEmail)
                    .limit(1)
                    .get();

                if (userQuery.docs.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                        content: Text("User not found in users collection")),
                  );
                  return;
                }

                final userDoc = userQuery.docs.first;
                final uid = userDoc.id;
                final userData = userDoc.data();

                final groupRef =
                FirebaseFirestore.instance.collection('groups').doc(groupId);

                await groupRef.collection('members').doc(uid).set({
                  'uid': uid,
                  'name': userData['fullName'] ??
                      userData['username'] ??
                      userData['email'],
                  'email': userData['email'] ?? '',
                  'addedAt': FieldValue.serverTimestamp(),
                });

                await groupRef.update({
                  'members': FieldValue.arrayUnion([uid])
                });

                Navigator.pop(context);
              },
              child: const Text("Add"),
            ),
          ],
        );
      },
    );
  }
  Future<void> _generateAndSavePDF(BuildContext context, String groupId, String groupName) async {
    try {
      // Fetch group document (for members list)
      final groupDoc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .get();

      final groupData = groupDoc.data() ?? {};
      final memberIds = List<String>.from(groupData['members'] ?? []);

      // Fetch member names from subcollection "members"
      final membersSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('members')
          .get();

      final memberMap = {
        for (var doc in membersSnapshot.docs)
          doc.id: (doc.data()['name'] ?? doc.data()['email'] ?? "Unknown")
      };

      // Fetch expenses
      final snapshot = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('expenses')
          .orderBy('timestamp', descending: true)
          .get();

      final expenses = snapshot.docs;

      if (expenses.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("No expenses to generate PDF")),
        );
        return;
      }

      // Create PDF document
      final pdf = pw.Document();

      pdf.addPage(
        pw.MultiPage(
          build: (context) => [
            pw.Header(level: 0, child: pw.Text("Expenses for $groupName")),
            pw.TableHelper.fromTextArray(
              headers: ["Title", "Amount", "Currency", "Paid By"],
              data: expenses.map((doc) {
                final data = doc.data() as Map<String, dynamic>;
                final paidById = data['paidBy'];
                final paidByName = data['paidByName'] ??
                    memberMap[paidById] ??
                    paidById ??
                    "Unknown";

                return [
                  data['title'] ?? "Untitled",
                  (data['amount'] ?? 0).toString(),
                  data['currency'] ?? "",
                  paidByName,
                ];
              }).toList(),
            ),
            pw.SizedBox(height: 20),
            pw.Header(level: 1, child: pw.Text("Group Members")),
            pw.Bullet(
              text: memberIds.map((id) => memberMap[id] ?? id).join(", "),
            ),
          ],
        ),
      );

      // Save file locally

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error generating PDF: $e")),
      );
    }
  }
  @override
  Widget build(BuildContext context) {
    final groupName = widget.groupData['name'] ?? 'Unnamed Group';
    final groupId = widget.groupData.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(groupName),
        backgroundColor: Colors.black,
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add),
            tooltip: "Add Members",
            onPressed: () => _showAddMemberDialog(groupId),
          ),
          IconButton(
            icon: const Icon(Icons.share),
            tooltip: "Share Expenses PDF",
            onPressed: () => _generateAndSavePDF(context, groupId, groupName),
          ),
        ],
      ),
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Members",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 80,
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .doc(groupId)
                    .collection('members')
                    .orderBy('addedAt', descending: false)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                        child: CircularProgressIndicator(color: Colors.amber));
                  }

                  if (snapshot.hasError) {
                    return const Center(
                        child: Text("Error loading members",
                            style: TextStyle(color: Colors.red)));
                  }

                  final members = snapshot.data?.docs ?? [];

                  if (members.isEmpty) {
                    return const Center(
                        child: Text("No members yet",
                            style: TextStyle(color: Colors.white70)));
                  }

                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: members.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (context, index) {
                      final data =
                      members[index].data() as Map<String, dynamic>;
                      final name = data['name'] ?? 'Unknown';
                      final email = data['email'] ?? '';

                      return GestureDetector(
                        onLongPress: () {
                          showModalBottomSheet(
                            context: context,
                            builder: (_) {
                              return SafeArea(
                                child: Wrap(
                                  children: [
                                    ListTile(
                                      leading: const Icon(Icons.edit, color: Colors.blue),
                                      title: const Text("Update Member"),
                                      onTap: () {
                                        Navigator.pop(context);
                                        _showUpdateMemberDialog(groupId, members[index].id, data);
                                      },
                                    ),
                                    ListTile(
                                      leading: const Icon(Icons.delete, color: Colors.red),
                                      title: const Text("Delete Member"),
                                      onTap: () async {
                                        Navigator.pop(context);
                                        await FirebaseFirestore.instance
                                            .collection('groups')
                                            .doc(groupId)
                                            .collection('members')
                                            .doc(members[index].id)
                                            .delete();

                                        await FirebaseFirestore.instance
                                            .collection('groups')
                                            .doc(groupId)
                                            .update({
                                          "members": FieldValue.arrayRemove([members[index].id])
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey[900],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(name,
                                  style: const TextStyle(
                                      color: Colors.white, fontWeight: FontWeight.bold)),
                              Text(email,
                                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
                            ],
                          ),
                        ),
                      );

                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              "Expenses",
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('groups')
                    .doc(groupId)
                    .collection('expenses')
                    .orderBy('timestamp', descending: true)
                    .snapshots(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.amber),
                    );
                  }

                  if (snapshot.hasError) {
                    return const Center(
                      child: Text(
                        "Error loading expenses",
                        style: TextStyle(color: Colors.red),
                      ),
                    );
                  }

                  final docs = snapshot.data?.docs ?? [];

                  if (docs.isEmpty) {
                    return const Center(
                      child: Text(
                        "No expenses added yet",
                        style: TextStyle(color: Colors.white70),
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: docs.length,
                    separatorBuilder: (_, __) => const Divider(color: Colors.grey),
                    itemBuilder: (context, index) {
                      final doc = docs[index];
                      final data = doc.data() as Map<String, dynamic>? ?? {};

                      final title = data['title'] ?? 'Untitled';
                      final amount = (data['amount'] ?? 0).toDouble();
                      final symbol = data['symbol'] ?? '₹';
                      final currency = data['currency'] ?? '';
                      final isSplitEqually = data['splitEqually'] ?? true;

                      final paidById = data['paidBy'];

                      return FutureBuilder<DocumentSnapshot>(
                        future: FirebaseFirestore.instance
                            .collection('groups')
                            .doc(groupId)
                            .collection('members')
                            .doc(paidById)
                            .get(),
                        builder: (context, memberSnap) {
                          String paidByName = "Unknown";
                          if (memberSnap.hasData && memberSnap.data!.exists) {
                            final memberData =
                            memberSnap.data!.data() as Map<String, dynamic>?;
                            paidByName = memberData?['name'] ?? "Unknown";
                          }

                          return GestureDetector(
                            onLongPress: () {
                              showModalBottomSheet(
                                context: context,
                                builder: (_) {
                                  return SafeArea(
                                    child: Wrap(
                                      children: [
                                        ListTile(
                                          leading: const Icon(Icons.edit, color: Colors.blue),
                                          title: const Text("Update Expense"),
                                          onTap: () {
                                            Navigator.pop(context);
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => AddExpensePage(
                                                  groupId: groupId,
                                                  groupName: groupName,
                                                  existingExpense: doc, // pass expense for editing
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                        ListTile(
                                          leading: const Icon(Icons.delete, color: Colors.red),
                                          title: const Text("Delete Expense"),
                                          onTap: () async {
                                            Navigator.pop(context);
                                            await FirebaseFirestore.instance
                                                .collection('groups')
                                                .doc(groupId)
                                                .collection('expenses')
                                                .doc(doc.id)
                                                .delete();
                                          },
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              );
                            },
                            child: ListTile(
                              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                              title: Text(
                                title,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    "Paid by $paidByName",
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                  Text(
                                    isSplitEqually ? "Split equally" : "Split manually",
                                    style: const TextStyle(
                                      color: Colors.white54,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                              trailing: Text(
                                '$symbol$amount $currency',
                                style: const TextStyle(
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => ExpenseDetailPage(
                                      groupId: groupId,
                                      expenseId: doc.id,
                                    ),
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      );
                    },
                  );
                },
              ),
            )
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.amber,
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  AddExpensePage(groupId: groupId, groupName: groupName),
            ),
          );
        },
        child: const Icon(Icons.add, color: Colors.black),
      ),
    );
  }
}
