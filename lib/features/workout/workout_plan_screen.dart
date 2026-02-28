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

  // ── THEME ─────────────────────────────────────────────────────────────────
  static const _orange    = Color(0xFFFF5E00);
  static const _volt      = Color(0xFFB9FF2B);
  static const _bg        = Color(0xFF0D0D0D);
  static const _surface   = Color(0xFF1A1A1A);

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
      p:        const TextStyle(color: const Color(0xFFFFFFFF), fontSize: 14, height: 1.7),
      h1:       const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800, height: 2),
      h2:       TextStyle(color: _orange, fontSize: 17, fontWeight: FontWeight.w700, height: 2),
      h3:       const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.8),
      strong:   const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
      em:       const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
      listBullet: TextStyle(color: _volt, fontSize: 14),
      tableHead: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
      tableBody: const TextStyle(color: const Color(0xFFFFFFFF), fontSize: 13),
      tableBorder: TableBorder.all(color: Colors.white12, width: 1),
      tableHeadAlign: TextAlign.left,
      blockquoteDecoration: BoxDecoration(
        color: _orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: _orange, width: 3)),
      ),
      blockquotePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      blockquote: const TextStyle(color: Colors.white70, fontSize: 14),
      code: const TextStyle(color: Color(0xFFB9FF2B), fontSize: 13, fontFamily: 'monospace'),
      codeblockDecoration: BoxDecoration(color: const Color(0xFF111111), borderRadius: BorderRadius.circular(8)),
      horizontalRuleDecoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white12, width: 1))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
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
            icon: const Icon(Icons.add_circle_outline, color: _orange, size: 24),
            tooltip: 'Generate New Plan',
            onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _orange,
          indicatorWeight: 2,
          labelColor: _orange,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'Current Plan'), Tab(text: 'My History')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildCurrentPlan(context), _buildHistory(context)],
      ),
    );
  }

  // ── CURRENT PLAN TAB ──────────────────────────────────────────────────────
  Widget _buildCurrentPlan(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Orange AI banner (friend's design)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: _orange.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _orange.withOpacity(0.5)),
            ),
            child: Row(children: [
              const Icon(Icons.auto_awesome, color: _orange, size: 20),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'AI-Generated based on your specific goals and injury profile.',
                  style: TextStyle(color: _orange, fontSize: 13, fontWeight: FontWeight.w600, height: 1.4),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: _volt.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _volt.withOpacity(0.5)),
                ),
                child: const Text('Saved ✓',
                    style: TextStyle(color: _volt, fontSize: 11, fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
          const SizedBox(height: 16),

          // Volt green glow plan card (friend's design) + markdown rendering (yours)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _volt.withOpacity(0.3), width: 1.5),
              boxShadow: [
                BoxShadow(color: _volt.withOpacity(0.05), blurRadius: 20, spreadRadius: 2),
              ],
            ),
            child: MarkdownBody(
              data: widget.plan,
              styleSheet: _mdStyle(context),
              shrinkWrap: true,
              selectable: true,
            ),
          ),
          const SizedBox(height: 20),

          // Generate new plan button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              onPressed: () => Navigator.popUntil(context, (route) => route.isFirst),
              style: ElevatedButton.styleFrom(
                backgroundColor: _orange,
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

  // ── HISTORY TAB ───────────────────────────────────────────────────────────
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
          return Center(child: CircularProgressIndicator(color: _orange));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.history, size: 60, color: Colors.white12),
              SizedBox(height: 16),
              Text('No saved plans yet', style: TextStyle(color: Colors.white38, fontSize: 16)),
            ]),
          );
        }

        final docs = snapshot.data!.docs;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data          = docs[index].data() as Map<String, dynamic>;
            final isCurrentPlan = docs[index].id == widget.planId;
            final createdAt     = data['createdAt'] as Timestamp?;
            final dateStr       = createdAt != null ? _formatDate(createdAt.toDate()) : 'Recently';

            return GestureDetector(
              onTap: () => _showPlanModal(context, data, isCurrentPlan),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isCurrentPlan ? _orange.withOpacity(0.08) : _surface,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: isCurrentPlan ? _orange.withOpacity(0.5) : Colors.white12,
                    width: isCurrentPlan ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  // Index badge
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: isCurrentPlan ? _orange.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(child: Text('${index + 1}',
                        style: TextStyle(
                          color: isCurrentPlan ? _orange : Colors.white54,
                          fontWeight: FontWeight.w800, fontSize: 16))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(
                        child: Text(data['goal'] ?? 'Workout Plan',
                            style: TextStyle(
                              color: isCurrentPlan ? Colors.white : Colors.white70,
                              fontWeight: FontWeight.w700, fontSize: 14),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (isCurrentPlan)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _orange.withOpacity(0.2),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Text('Current',
                              style: TextStyle(color: _orange, fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                    ]),
                    const SizedBox(height: 4),
                    Text(
                      '${data['daysPerWeek'] ?? '?'} days · ${data['duration'] ?? '?'} · ${data['fitnessLevel'] ?? '?'}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                    const SizedBox(height: 2),
                    Text(dateStr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ])),
                  const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
                ]),
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
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(children: [
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40, height: 4,
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(data['goal'] ?? 'Workout Plan',
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  Text('${data['daysPerWeek']} days/week · ${data['duration']} · ${data['fitnessLevel']}',
                      style: const TextStyle(color: Colors.white54, fontSize: 13)),
                ])),
                if (isCurrent)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: _volt.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text('Active',
                        style: TextStyle(color: _volt, fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
              ]),
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
          ]),
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now  = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}