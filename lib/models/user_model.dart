class UserModel {
  final String uid;
  final String name;
  final List<String> physicalLimitations;
  final int fatigueScore; // 1–10
  final int currentStreak;

  UserModel({
    required this.uid,
    required this.name,
    required this.physicalLimitations,
    required this.fatigueScore,
    required this.currentStreak,
  });

  Map<String, dynamic> toMap() => {
    'uid': uid,
    'name': name,
    'physical_limitations': physicalLimitations,
    'fatigue_score': fatigueScore,
    'current_streak': currentStreak,
  };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
    uid: map['uid'] ?? '',
    name: map['name'] ?? '',
    physicalLimitations: List<String>.from(map['physical_limitations'] ?? []),
    fatigueScore: map['fatigue_score'] ?? 5,
    currentStreak: map['current_streak'] ?? 0,
  );
}