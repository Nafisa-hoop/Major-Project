import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:rxdart/rxdart.dart';
import 'package:splitnow/screens/StatsPage.dart';
import 'package:splitnow/screens/ReceivablesPage.dart';
import 'package:splitnow/screens/SettingsPage.dart';
import 'package:splitnow/screens/StatsPage.dart';
import 'package:splitnow/screens/profile_page.dart';

import 'AllGroupsDuePage.dart';
import 'GroupDetailPage.dart';
import 'RecentActivityPage.dart';
import 'create_group_page.dart';

class HomeWidget extends StatefulWidget {
  const HomeWidget({super.key, required username});

  @override
  State<HomeWidget> createState() => _HomeWidgetState();
}

class _HomeWidgetState extends State<HomeWidget> {
  int _selectedIndex = 0;
  String? username;
  bool isLoading = true;

  // New state variables
  double paidAmount = 0;
  double dueAmount = 0;
  void _onBottomNavTap(int index) {
    setState(() => _selectedIndex = index);
  }

  Future<void> fetchUsername() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) {
        final doc =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        setState(() {
          username = doc['fullName'] ?? 'User';
          isLoading = false;
        });
      } else {
        username = 'User';
        isLoading = false;
      }
    } catch (e) {
      print("Error fetching username: $e");
      username = 'User';
      isLoading = false;
    }
  }

  @override
  void initState() {
    super.initState();
    fetchUsername();
  }

  Future<List<Map<String, dynamic>>> getRecentExpenses(String uid) async {
    List<Map<String, dynamic>> allExpenses = [];

    try {
      final groupsSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: uid)
          .get();

      for (var groupDoc in groupsSnapshot.docs) {
        final expensesSnapshot =
        await groupDoc.reference.collection('expenses').get();

        for (var expDoc in expensesSnapshot.docs) {
          final data = expDoc.data();
          data['groupName'] = groupDoc['name'] ?? "Unnamed Group";
          data['id'] = expDoc.id;
          allExpenses.add(data);
        }
      }

      // Sort by timestamp (descending)
      allExpenses.sort((a, b) {
        final tsA = a['timestamp'] as Timestamp?;
        final tsB = b['timestamp'] as Timestamp?;
        if (tsA == null || tsB == null) return 0;
        return tsB.compareTo(tsA); // latest first
      });
    } catch (e) {
      print("⚠️ Error fetching recent expenses: $e");
    }

    return allExpenses.take(5).toList(); // limit to 5 recent
  }
  // Fetch total paid and due
  Future<Map<String, double>> getExpensesSummary(String uid) async {
    double totalPaid = 0;
    double totalDue = 0;

    try {
      // 1. Get all groups where user is a member
      final groupsSnapshot = await FirebaseFirestore.instance
          .collection('groups')
          .where('members', arrayContains: uid) // ✅ this checks group.members
          .get();

      for (var groupDoc in groupsSnapshot.docs) {
        // 2. Loop through each expense in group
        final expensesSnapshot =
        await groupDoc.reference.collection('expenses').get();

        for (var expDoc in expensesSnapshot.docs) {
          final data = expDoc.data();

          // ✅ This is the important part: read expense.members array
          final members = List<Map<String, dynamic>>.from(data['members'] ?? []);

          for (var member in members) {
            if (member['memberId'] == uid) {
              totalPaid += (member['paid'] ?? 0).toDouble();
              totalDue += (member['owed'] ?? 0).toDouble();
            }
          }
        }
      }
    } catch (e) {
      print("⚠️ Error fetching expenses summary: $e");
    }

    return {"paid": totalPaid, "due": totalDue};
  }


  /// ✅ Group-level summary (Paid, Due, Receivable) with per-member settlement
  Stream<Map<String, double>> watchExpensesSummary(String uid) async* {
    final groupsSnapshot = await FirebaseFirestore.instance
        .collection('groups')
        .where('members', arrayContains: uid)
        .get();

    final expenseStreams = groupsSnapshot.docs
        .map((g) => g.reference.collection('expenses').snapshots())
        .toList();

    if (expenseStreams.isEmpty) {
      yield {"paid": 0.0, "due": 0.0, "receivable": 0.0};
      return;
    }

    double _asDouble(dynamic v) {
      if (v == null) return 0.0;
      if (v is num) return v.toDouble();
      return double.tryParse(v.toString()) ?? 0.0;
    }

    yield* Rx.combineLatestList(expenseStreams).map((snapshotsList) {
      double totalPaid = 0.0;

      // Net balance per counterparty: +ve => they owe me, -ve => I owe them
      final Map<String, double> netWith = {};

      for (final snapshot in snapshotsList) {
        for (final expDoc in snapshot.docs) {
          final data = expDoc.data() as Map<String, dynamic>;
          final List<dynamic> splits = (data['splits'] ?? []) as List<dynamic>;
          if (splits.isEmpty) continue;

          // Build paid/owed per member for this expense
          final Map<String, double> paid = {};
          final Map<String, double> owed = {};
          for (final s in splits) {
            final m = s is Map ? s['memberId'] as String? : null;
            if (m == null) continue;
            paid[m] = (paid[m] ?? 0) + _asDouble(s['paid']);
            owed[m] = (owed[m] ?? 0) + _asDouble(s['owed']);
          }

          if (!paid.containsKey(uid) && !owed.containsKey(uid)) continue;

          totalPaid += (paid[uid] ?? 0.0);

          // delta = paid - owed for each member (creditor if >0, debtor if <0)
          final Map<String, double> delta = {};
          for (final m in {...paid.keys, ...owed.keys}) {
            delta[m] = (paid[m] ?? 0.0) - (owed[m] ?? 0.0);
          }

          double myDelta = delta[uid] ?? 0.0;
          if (myDelta == 0) continue;

          if (myDelta > 0) {
            // I overpaid -> allocate to debtors
            double remaining = myDelta;
            for (final entry in delta.entries.where((e) => e.key != uid && e.value < 0)) {
              if (remaining <= 0) break;
              final other = entry.key;
              final need = -entry.value; // how much they underpaid
              final transfer = remaining < need ? remaining : need;
              if (transfer <= 0) continue;

              netWith[other] = (netWith[other] ?? 0.0) + transfer; // they owe me
              remaining -= transfer;
            }
          } else {
            // I underpaid -> allocate to creditors
            double remaining = -myDelta;
            for (final entry in delta.entries.where((e) => e.key != uid && e.value > 0)) {
              if (remaining <= 0) break;
              final other = entry.key;
              final canCover = entry.value; // how much they overpaid
              final transfer = remaining < canCover ? remaining : canCover;
              if (transfer <= 0) continue;

              netWith[other] = (netWith[other] ?? 0.0) - transfer; // I owe them
              remaining -= transfer;
            }
          }
        }
      }

      double totalReceivable = 0.0;
      double totalDue = 0.0;
      netWith.forEach((_, amt) {
        if (amt > 0) totalReceivable += amt;
        if (amt < 0) totalDue += -amt;
      });

      // Round/display helper (change precision if you need more decimals)
      double out(double x) =>
          (x.abs() < 0.0005) ? 0.0 : double.parse(x.toStringAsFixed(2));

      return {
        "paid": out(totalPaid),
        "due": out(totalDue),
        "receivable": out(totalReceivable),
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

    final pages = [
      _homeTab(username ?? 'User'),
      _groupsTab(),
      _statsTab(),
      _accountTab(),
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Theme.of(context).appBarTheme.backgroundColor,
        title: Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                username ?? 'User',
                style: const TextStyle(color: Colors.white, fontSize: 18),
                overflow: TextOverflow.ellipsis,
              ),
              const Text(
                "Welcome back!",
                style: TextStyle(color: Colors.white70, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.white),
            tooltip: "Settings",
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            tooltip: "Logout",
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              Navigator.pushReplacementNamed(context, '/login');
            },
          ),
        ],
      ),
      body: SafeArea(child: pages[_selectedIndex]),
      bottomNavigationBar: BottomNavigationBar(
        backgroundColor: Colors.grey[900],
        selectedItemColor: Colors.amberAccent,
        unselectedItemColor: Colors.grey[500],
        selectedIconTheme: const IconThemeData(size: 28),
        unselectedIconTheme: const IconThemeData(size: 24),
        type: BottomNavigationBarType.fixed,
        currentIndex: _selectedIndex,
        onTap: _onBottomNavTap,
        items: [
          _bottomNavItem(Icons.home, "Home", 0),
          _bottomNavItem(Icons.group, "Groups", 1),
          _bottomNavItem(Icons.pie_chart, "Stats", 2),
          _bottomNavItem(Icons.account_box, "Account", 3),
        ],
      ),
    );
  }

  Widget _homeTab(String username) {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Carousel
          SizedBox(
            height: 140,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _carouselCard("assets/image/onboarding1.png", "Add Friends"),
                _carouselCard("assets/image/onboarding2.png", "Split Now"),
                _carouselCard("assets/image/onboarding.png", "Create Group"),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Featured
          // 🔹 Featured
          const Text(
            "Featured",
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),

          StreamBuilder<Map<String, double>>(
            stream: watchExpensesSummary(uid!),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.amber));
              }

              if (snapshot.hasError) {
                return const Text("Error loading expenses",
                    style: TextStyle(color: Colors.red));
              }

              final data = snapshot.data ??
                  {"paid": 0.0, "due": 0.0, "receivable": 0.0};

              return Row(
                children: [
                  Expanded(
                    child: _featuredCard(
                      "Due",
                      data["due"] ?? 0.0,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AllGroupsDuePage(uid: uid),
                          ),
                        );
                      },
                    ),
                  ),
                  Expanded(
                    child: _featuredCard("Paid", data["paid"] ?? 0.0),
                  ),
                  Expanded(
                    child: _featuredCard(
                      "Receivable",
                      data["receivable"] ?? 0.0,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => ReceivablesPage(uid: uid),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),

          const SizedBox(height: 24),

          // Recent Activity
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Recent activity",
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              GestureDetector(
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => RecentActivityPage(uid: uid),
                    ),
                  );
                },
                child: const Text("View all",
                    style: TextStyle(
                        color: Colors.white70,
                        decoration: TextDecoration.underline)),
              ),
            ],
          ),
          const SizedBox(height: 12),

          FutureBuilder<List<Map<String, dynamic>>>(future: getRecentExpenses(uid),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                    child: CircularProgressIndicator(color: Colors.amber));
              }

              if (snapshot.hasError) {
                return const Text("Error loading activity",
                    style: TextStyle(color: Colors.red));
              }

              final expenses = snapshot.data ?? [];

              if (expenses.isEmpty) {
                return const Text("No recent activity",
                    style: TextStyle(color: Colors.white70));
              }

              return ListView.builder(
                itemCount: expenses.length,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemBuilder: (context, index) {
                  final exp = expenses[index];
                  return _activityCard(
                    title: exp['description'] ?? "Expense",
                    amount: (exp['amount'] ?? 0).toDouble(),
                    groupName: exp['groupName'] ?? "Group",
                    timestamp: exp['timestamp'] != null
                        ? (exp['timestamp'] as Timestamp).toDate()
                        : null,
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }

// 🔹 FeaturedCard with amount
  Widget _featuredCard(String label, double amount, {VoidCallback? onTap}) {
    final Color valueColor = (label == "Due")
        ? Colors.red
        : (label == "Receivable" ? Colors.green : Colors.amber);

    return GestureDetector(
      onTap: onTap, // ✅ Use the callback
      child: Container(
        constraints: const BoxConstraints(minWidth: 100, maxWidth: 120),
        height: 90,
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                "₹${amount.toStringAsFixed(2)}",
                style: TextStyle(
                  color: valueColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _activityCard({
    required String title,
    required double amount,
    required String groupName,
    DateTime? timestamp,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(groupName,
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text("₹${amount.toStringAsFixed(2)}",
                  style: const TextStyle(
                      color: Colors.amber,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              if (timestamp != null)
                Text(
                  "${timestamp.day}/${timestamp.month}/${timestamp.year}",
                  style: const TextStyle(color: Colors.white54, fontSize: 11),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _carouselCard(String imagePath, String buttonLabel) {
    return Container(
      margin: const EdgeInsets.only(right: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(16),
      ),
      width: 300,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Image.asset(imagePath, height: 130),
          ElevatedButton(
            onPressed: () {
              // Inside your widget, for example in a button onTap:
              setState(() {
                _selectedIndex = 1; // Groups tab index
              });

            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.transparent,
              elevation: 0,
              side: const BorderSide(color: Colors.white),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
            ),
            child:
                Text(buttonLabel, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
  Widget _statsTab() {
    return StatsPage();
  }


  BottomNavigationBarItem _bottomNavItem(
      IconData icon, String label, int index) {
    final isSelected = _selectedIndex == index;
    return BottomNavigationBarItem(
      icon: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
        decoration: BoxDecoration(
          color: isSelected ? Colors.grey[800] : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon),
      ),
      label: label,
    );
  }

  Widget _groupCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey[900],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.amberAccent, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 16)),
                  const SizedBox(height: 4),
                  Text(subtitle,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white),
          ],
        ),
      ),
    );
  }
  // Account tab content
  Widget _accountTab() {
    return ProfilePage(
      onProfileUpdated: () {
        fetchUsername();
      },
    );
  }


  Widget _groupsTab() {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            "Groups",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 24,
            ),
          ),
          const SizedBox(height: 16),
          _groupCard(
            title: "Create Group",
            subtitle: "Start a new group",
            icon: Icons.group_add,
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CreateGroupPage(),
                ),
              ).then((_) => setState(() {}));
            },
          ),
          const SizedBox(height: 24),
          const Text(
            "Your Groups",
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 12),
          FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance
                .collection('groups')
                .where('members', arrayContains: uid)
                .get(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(
                  child: CircularProgressIndicator(color: Colors.amber),
                );
              }

              if (snapshot.hasError) {
                return const Text(
                  "Error loading groups",
                  style: TextStyle(color: Colors.red),
                );
              }

              final docs = snapshot.data?.docs ?? [];

              if (docs.isEmpty) {
                return const Text(
                  "No groups found",
                  style: TextStyle(color: Colors.white70),
                );
              }

              return ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                itemBuilder: (context, index) {
                  final group = docs[index];
                  return InkWell(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupDetailPage(groupData: group),
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 8),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.group,
                              color: Colors.amberAccent, size: 32),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group['name'] ?? 'Unnamed Group',
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 16),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  group['type'] ?? '',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          const Icon(Icons.chevron_right, color: Colors.white),
                        ],
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
    );
  }
}
