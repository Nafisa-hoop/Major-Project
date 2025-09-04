import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';

import 'EditProfilePage.dart';
import 'create_group_page.dart';
class ProfilePage extends StatefulWidget {
  const ProfilePage({Key? key, this.onProfileUpdated}) : super(key: key);
  final VoidCallback? onProfileUpdated;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  String username = 'User';
  String email = '';
  int totalGroups = 0;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    fetchUsernameAndEmail();
    fetchTotalGroups();
  }

  Future<void> fetchUsernameAndEmail() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        setState(() {
          username = doc.data()?['fullName'] ?? 'User';
          email = user.email ?? '';
        });
      }
    } catch (e) {
      debugPrint("Error fetching username/email: $e");
    }
  }

  Future<void> fetchTotalGroups() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final groupsSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: user.uid)
          .get();

      setState(() {
        totalGroups = groupsSnapshot.docs.length;
        isLoading = false;
      });
    } catch (e) {
      debugPrint("Error fetching groups: $e");
      setState(() => isLoading = false);
    }
  }

  Stream<Map<String, double>> watchExpensesSummary() async* {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      yield {"paid": 0.0, "due": 0.0};
      return;
    }

    final groupsSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: user.uid)
        .get();

    final expenseStreams = groupsSnapshot.docs
        .map((g) => g.reference.collection('expenses').snapshots())
        .toList();

    if (expenseStreams.isEmpty) {
      yield {"paid": 0.0, "due": 0.0};
      return;
    }

    double _asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    yield* Rx.combineLatestList(expenseStreams).map((snapshotsList) {
      double totalPaid = 0.0;
      double totalDue = 0.0;

      for (final snapshot in snapshotsList) {
        for (final expDoc in snapshot.docs) {
          final data = expDoc.data();
          final splits = (data['splits'] ?? []) as List<dynamic>;
          final mySplit = splits.cast<Map<String, dynamic>?>().firstWhere(
                  (s) => s?['memberId'] == user.uid,
              orElse: () => null);

          if (mySplit != null) {
            final paid = _asDouble(mySplit['paid']);
            final owed = _asDouble(mySplit['owed']);
            totalPaid += paid;
            if (owed > paid) totalDue += owed - paid;
          }
        }
      }

      return {
        "paid": double.parse(totalPaid.toStringAsFixed(2)),
        "due": double.parse(totalDue.toStringAsFixed(2)),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator(color: Colors.amber)),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Profile header
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Icon(Icons.account_circle, size: 80, color: Colors.grey[700]),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: IconButton(
                        icon: const Icon(Icons.edit, color: Colors.amber),
                        onPressed: () async {
                          final updated = await Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const EditProfilePage()),
                          );
                          if (updated == true) {
                            fetchUsernameAndEmail();
                            fetchTotalGroups();
                            widget.onProfileUpdated?.call();
                          }
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(email,
                          style:
                          const TextStyle(color: Colors.white70, fontSize: 14)),
                    ],
                  ),
                )
              ],
            ),
            const SizedBox(height: 20),

            // Quick stats using StreamBuilder
            StreamBuilder<Map<String, double>>(
              stream: watchExpensesSummary(),
              builder: (context, snapshot) {
                final data = snapshot.data ?? {"paid": 0.0, "due": 0.0};
                return Row(
                  children: [
                    Expanded(
                        child: _buildStatCard(
                            "Groups", "$totalGroups", Colors.amber)),
                    Expanded(
                        child: _buildStatCard(
                            "Paid by You", "₹${data['paid']}", Colors.green)),
                    Expanded(
                        child: _buildStatCard(
                            "Your Due", "₹${data['due']}", Colors.red)),
                  ],
                );
              },
            ),

            const SizedBox(height: 20),

            // Quick Actions
            const Text("Quick Actions",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ListTile(
              leading: const Icon(Icons.group_add, color: Colors.amber),
              title: const Text("Create Group",
                  style: TextStyle(color: Colors.white)),
              onTap: () => Navigator.push(
                  context, MaterialPageRoute(builder: (_) => const CreateGroupPage())),
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.redAccent),
              title:
              const Text("Logout", style: TextStyle(color: Colors.white)),
              onTap: () async {
                await FirebaseAuth.instance.signOut();
                Navigator.pushReplacementNamed(context, '/login');
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String value, Color color) {
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                color: color, fontSize: 18, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text(title, style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ],
    );
  }
}
