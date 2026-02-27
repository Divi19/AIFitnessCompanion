import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class InjuryProfileScreen extends StatefulWidget {
  const InjuryProfileScreen({Key? key}) : super(key: key);

  @override
  _InjuryProfileScreenState createState() => _InjuryProfileScreenState();
}

class _InjuryProfileScreenState extends State<InjuryProfileScreen> {
  // --- CLINICAL VARIABLES ---
  
  // Upper Body Kinetics
  bool rotatorCuff = false;
  bool deltoids = false;
  bool pectorals = false;
  bool biceps = false;
  bool triceps = false;
  bool latsRhomboids = false; // Upper Back
  bool elbowJoint = false;
  bool wristCarpals = false;

  // Lower Body Kinetics
  bool glutesPelvis = false;
  bool quadriceps = false;
  bool hamstrings = false;
  bool calves = false;
  bool kneeMeniscus = false;
  bool achillesAnkle = false;
  bool plantarFoot = false;

  // Spinal & Core Integrity
  bool cervicalSpine = false; // Neck
  bool thoracicSpine = false; // Mid-Back
  bool lumbarSpine = false;   // Lower Back
  bool abdominalHernia = false;

  // Systemic & Mobility
  bool cardiovascular = false; // Heart condition
  bool respiratoryAsthma = false;
  bool osteoarthritis = false;
  bool usesWheelchair = false;
  bool usesProsthetic = false;
  
  // Custom Input
  final TextEditingController _clinicalNotesController = TextEditingController();

  @override
  void dispose() {
    _clinicalNotesController.dispose();
    super.dispose();
  }

  // --- CUSTOM COMPACT WIDGETS ---
  Widget _buildCompactCheckbox(String title, bool value, Function(bool?) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            height: 24,
            width: 24,
            child: Checkbox(
              value: value, 
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              activeColor: Colors.blue[800],
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              title, 
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactSwitch(String title, bool value, Function(bool) onChanged) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
          SizedBox(
            height: 30,
            child: Switch(
              value: value, 
              onChanged: onChanged,
              activeColor: Colors.blue[800],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Clinical Biometrics Profile"),
        backgroundColor: Colors.blue[900], // Darker, more professional blue
        elevation: 0,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Biomechanical Assessment",
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.black87),
              ),
              const SizedBox(height: 8),
              const Text(
                "Select all active contraindications or anatomical limitations. Our AI architecture will strictly filter contraindicated movements to prevent re-injury.",
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 20),
              
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  
                  // --- LEFT COLUMN (Upper Body & Spine) ---
                  Expanded(
                    child: Column(
                      children: [
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Upper Body Kinetics", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
                                const Divider(),
                                _buildCompactCheckbox("Rotator Cuff / Shoulder", rotatorCuff, (val) => setState(() => rotatorCuff = val!)),
                                _buildCompactCheckbox("Deltoids", deltoids, (val) => setState(() => deltoids = val!)),
                                _buildCompactCheckbox("Pectorals (Chest)", pectorals, (val) => setState(() => pectorals = val!)),
                                _buildCompactCheckbox("Biceps Brachii", biceps, (val) => setState(() => biceps = val!)),
                                _buildCompactCheckbox("Triceps Brachii", triceps, (val) => setState(() => triceps = val!)),
                                _buildCompactCheckbox("Lats / Rhomboids", latsRhomboids, (val) => setState(() => latsRhomboids = val!)),
                                _buildCompactCheckbox("Elbow Joint", elbowJoint, (val) => setState(() => elbowJoint = val!)),
                                _buildCompactCheckbox("Wrist / Carpals", wristCarpals, (val) => setState(() => wristCarpals = val!)),
                              ],
                            ),
                          ),
                        ),
                        
                        const SizedBox(height: 10),
                        
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Spinal & Core Integrity", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
                                const Divider(),
                                _buildCompactCheckbox("Cervical (Neck)", cervicalSpine, (val) => setState(() => cervicalSpine = val!)),
                                _buildCompactCheckbox("Thoracic (Mid-Back)", thoracicSpine, (val) => setState(() => thoracicSpine = val!)),
                                _buildCompactCheckbox("Lumbar (Lower Back)", lumbarSpine, (val) => setState(() => lumbarSpine = val!)),
                                _buildCompactCheckbox("Abdominal Strain/Hernia", abdominalHernia, (val) => setState(() => abdominalHernia = val!)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(width: 10), // Column Buffer
                  
                  // --- RIGHT COLUMN (Lower Body & Medical) ---
                  Expanded(
                    child: Column(
                      children: [
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Lower Body Kinetics", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
                                const Divider(),
                                _buildCompactCheckbox("Glutes / Pelvis", glutesPelvis, (val) => setState(() => glutesPelvis = val!)),
                                _buildCompactCheckbox("Quadriceps", quadriceps, (val) => setState(() => quadriceps = val!)),
                                _buildCompactCheckbox("Hamstrings", hamstrings, (val) => setState(() => hamstrings = val!)),
                                _buildCompactCheckbox("Calves / Gastrocnemius", calves, (val) => setState(() => calves = val!)),
                                _buildCompactCheckbox("Knee / Meniscus", kneeMeniscus, (val) => setState(() => kneeMeniscus = val!)),
                                _buildCompactCheckbox("Achilles / Ankle", achillesAnkle, (val) => setState(() => achillesAnkle = val!)),
                                _buildCompactCheckbox("Plantar / Foot", plantarFoot, (val) => setState(() => plantarFoot = val!)),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 10),
                        
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text("Systemic & Mobility", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.blueGrey)),
                                const Divider(),
                                _buildCompactCheckbox("Cardiovascular", cardiovascular, (val) => setState(() => cardiovascular = val!)),
                                _buildCompactCheckbox("Respiratory / Asthma", respiratoryAsthma, (val) => setState(() => respiratoryAsthma = val!)),
                                _buildCompactCheckbox("Osteoarthritis", osteoarthritis, (val) => setState(() => osteoarthritis = val!)),
                                const SizedBox(height: 6),
                                _buildCompactSwitch("Wheelchair User", usesWheelchair, (val) => setState(() => usesWheelchair = val)),
                                _buildCompactSwitch("Uses Prosthesis", usesProsthetic, (val) => setState(() => usesProsthetic = val)),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                ],
              ),
              
              const SizedBox(height: 16),
              
              const Text("Clinical Notes / Custom Parameters", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.blueGrey)),
              const SizedBox(height: 8),
              TextField(
                controller: _clinicalNotesController,
                decoration: InputDecoration(
                  fillColor: Colors.white,
                  filled: true,
                  hintText: "Enter exact post-operative instructions or specific medical clearance notes...",
                  hintStyle: const TextStyle(fontSize: 13),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
                maxLines: 3,
              ),
              
              const SizedBox(height: 24),
              
              // DATABASE SAVE BUTTON
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue[900],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Encrypting and saving biometrics...')),
                    );

                    try {
                      // Save massive data payload to Firestore
                      await FirebaseFirestore.instance.collection('users').doc('user_123').set({
                        'biometrics': {
                          'upperBody': {
                            'rotatorCuff': rotatorCuff, 'deltoids': deltoids, 'pectorals': pectorals,
                            'biceps': biceps, 'triceps': triceps, 'latsRhomboids': latsRhomboids,
                            'elbowJoint': elbowJoint, 'wristCarpals': wristCarpals,
                          },
                          'lowerBody': {
                            'glutesPelvis': glutesPelvis, 'quadriceps': quadriceps, 'hamstrings': hamstrings,
                            'calves': calves, 'kneeMeniscus': kneeMeniscus, 'achillesAnkle': achillesAnkle,
                            'plantarFoot': plantarFoot,
                          },
                          'coreSpine': {
                            'cervicalSpine': cervicalSpine, 'thoracicSpine': thoracicSpine,
                            'lumbarSpine': lumbarSpine, 'abdominalHernia': abdominalHernia,
                          },
                          'systemic': {
                            'cardiovascular': cardiovascular, 'respiratoryAsthma': respiratoryAsthma,
                            'osteoarthritis': osteoarthritis, 'wheelchair': usesWheelchair,
                            'prosthesis': usesProsthetic,
                          },
                          'clinicalNotes': _clinicalNotesController.text,
                        },
                        'profile_completed': true, 
                      }, SetOptions(merge: true));

                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Clinical Profile Verified & Saved!')),
                      );
                    } catch (e) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  },
                  child: const Text("Verify & Save Profile", style: TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 40), 
            ],
          ),
        ),
      ),
    );
  }
}