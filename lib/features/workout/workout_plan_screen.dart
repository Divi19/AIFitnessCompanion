import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutPlanScreen extends StatefulWidget {
  final String plan;
  final String planId;
  final String uid;

  const WorkoutPlanScreen({
    Key? key,
    required this.plan,
    required this.planId,
    required this.uid,
  }) : super(key: key);

  @override
  State<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends State<WorkoutPlanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  MarkdownStyleSheet _mdStyle(BuildContext context) {
    return MarkdownStyleSheet(
      p: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 14, height: 1.7),
      h1: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 2),
      h2: const TextStyle(color: Color(0xFF4F8EF7), fontSize: 17, fontWeight: FontWeight.w700, height: 2),
      h3: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.8),
      strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      em: const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
      listBullet: const TextStyle(color: Color(0xFF4F8EF7), fontSize: 14),
      tableHead: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
      tableBody: const TextStyle(color: Color(0xFFFFFFFF), fontSize: 13),
      tableBorder: TableBorder.all(color: Colors.white12, width: 1),
      tableHeadAlign: TextAlign.left,
      blockquoteDecoration: BoxDecoration(
        color: const Color(0xFF4F8EF7).withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: const Border(left: BorderSide(color: Color(0xFF4F8EF7), width: 3)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      blockquote: const TextStyle(color: Colors.white70, fontSize: 14),
      code: const TextStyle(color: Color(0xFF4CAF50), fontSize: 13, fontFamily: 'monospace'),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0D1627),
        borderRadius: BorderRadius.circular(8),
      ),
      horizontalRuleDecoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0E1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Your Workout Plan',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline, color: Color(0xFF4F8EF7), size: 24),
            tooltip: 'Generate New Plan',
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF4F8EF7),
          indicatorWeight: 2,
          labelColor: const Color(0xFF4F8EF7),
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [
            Tab(text: 'Current Plan'),
            Tab(text: 'My History'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCurrentPlan(context),
          _buildHistory(context),
        ],
      ),
    );
  }

  Widget _buildCurrentPlan(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A2540), Color(0xFF0D1627)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFF4F8EF7).withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4F8EF7).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.fitness_center, color: Color(0xFF4F8EF7), size: 24),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI-Generated Plan',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 16)),
                      SizedBox(height: 2),
                      Text('Personalised for your body & goals',
                          style: TextStyle(color: Colors.white54, fontSize: 12)),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF4CAF50).withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFF4CAF50).withOpacity(0.5)),
                  ),
                  child: const Text('Saved ✓',
                      style: TextStyle(color: Color(0xFF4CAF50), fontSize: 11, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF151929),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: MarkdownBody(
              data: widget.plan,
              styleSheet: _mdStyle(context),
              shrinkWrap: true,
              selectable: true,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF4F8EF7),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              icon: const Icon(Icons.refresh, color: Colors.white, size: 20),
              label: const Text('Generate New Plan',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: Colors.white)),
            ),
          ),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildHistory(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(widget.uid)
          .collection('workout_plans')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF4F8EF7)));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.history, size: 60, color: Colors.white12),
                SizedBox(height: 16),
                Text('No saved plans yet', style: TextStyle(color: Colors.white38, fontSize: 16)),
              ],
            ),
          );
        }

        final docs = snapshot.data!.docs;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final isCurrentPlan = docs[index].id == widget.planId;
            final createdAt = data['createdAt'] as Timestamp?;
            final dateStr = createdAt != null ? _formatDate(createdAt.toDate()) : 'Recently';

            return GestureDetector(
              onTap: () => _showPlanModal(context, data, isCurrentPlan),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isCurrentPlan
                      ? const Color(0xFF4F8EF7).withOpacity(0.1)
                      : const Color(0xFF151929),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isCurrentPlan ? const Color(0xFF4F8EF7).withOpacity(0.5) : Colors.white12,
                    width: isCurrentPlan ? 1.5 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: isCurrentPlan
                            ? const Color(0xFF4F8EF7).withOpacity(0.2)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: Text('${index + 1}',
                          style: TextStyle(
                            color: isCurrentPlan ? const Color(0xFF4F8EF7) : Colors.white54,
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          )),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            Expanded(
                              child: Text(data['goal'] ?? 'Workout Plan',
                                style: TextStyle(
                                  color: isCurrentPlan ? Colors.white : Colors.white70,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isCurrentPlan)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF4F8EF7).withOpacity(0.2),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: const Text('Current',
                                    style: TextStyle(color: Color(0xFF4F8EF7), fontSize: 10, fontWeight: FontWeight.w700)),
                              ),
                          ]),
                          const SizedBox(height: 4),
                          Text(
                            '${data['daysPerWeek'] ?? '?'} days · ${data['duration'] ?? '?'} · ${data['fitnessLevel'] ?? '?'}',
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          const SizedBox(height: 2),
                          Text(dateStr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showPlanModal(BuildContext context, Map<String, dynamic> data, bool isCurrent) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.85,
        maxChildSize: 0.95,
        minChildSize: 0.5,
        builder: (_, controller) => Container(
          decoration: const BoxDecoration(
            color: Color(0xFF0F1524),
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40, height: 4,
                decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(data['goal'] ?? 'Workout Plan',
                              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          Text('${data['daysPerWeek']} days/week · ${data['duration']} · ${data['fitnessLevel']}',
                              style: const TextStyle(color: Colors.white54, fontSize: 13)),
                        ],
                      ),
                    ),
                    if (isCurrent)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: const Color(0xFF4CAF50).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: const Text('Active',
                            style: TextStyle(color: Color(0xFF4CAF50), fontSize: 12, fontWeight: FontWeight.w700)),
                      ),
                  ],
                ),
              ),
              const Divider(color: Colors.white12, height: 24),
              Expanded(
                child: SingleChildScrollView(
                  controller: controller,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: MarkdownBody(
                    data: data['plan'] ?? '',
                    styleSheet: _mdStyle(context),
                    shrinkWrap: true,
                    selectable: true,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}