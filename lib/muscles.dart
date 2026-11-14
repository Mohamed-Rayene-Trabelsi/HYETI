const muscles = [
  'Chest', 'Back', 'Shoulders', 'Biceps', 'Triceps', 'Forearms', //
  'Core', 'Glutes', 'Quads', 'Hamstrings', 'Calves',
];

class Exercise {
  const Exercise(this.name, this.dose, this.tip);
  final String name;
  final String dose;
  final String tip;
}

/// A short, balanced pick per muscle: one heavy compound first, then accessories.
const exercises = <String, List<Exercise>>{
  'Chest': [
    Exercise('Bench press', '4 × 6–8', 'Shoulder blades pinned back, bar to mid-chest.'),
    Exercise('Incline dumbbell press', '3 × 8–10', 'Bench at about 30°, for the upper chest.'),
    Exercise('Cable fly', '3 × 12–15', 'Slight bend in the elbows, squeeze at the middle.'),
    Exercise('Push-up', '3 × as many as you can', 'Body in one straight line, chest to the floor.'),
  ],
  'Back': [
    Exercise('Pull-up', '4 × 6–10', 'Start from a dead hang, pull elbows to your ribs.'),
    Exercise('Barbell row', '4 × 8', 'Flat back, pull the bar to your lower stomach.'),
    Exercise('Lat pulldown', '3 × 10–12', 'Lean back slightly, bar to the upper chest.'),
    Exercise('Seated cable row', '3 × 10–12', 'Pause with the shoulder blades squeezed.'),
  ],
  'Shoulders': [
    Exercise('Overhead press', '4 × 6–8', 'Brace your core, press straight up past your face.'),
    Exercise('Lateral raise', '4 × 12–15', 'Light weight, lead with the elbows, no swinging.'),
    Exercise('Face pull', '3 × 15', 'Pull the rope to eye level, elbows high.'),
    Exercise('Rear delt fly', '3 × 12–15', 'Hinge forward, open the arms out wide.'),
  ],
  'Biceps': [
    Exercise('Barbell curl', '3 × 8–10', 'Elbows stay by your sides, no leaning back.'),
    Exercise('Incline dumbbell curl', '3 × 10–12', 'Let the arms hang back for a full stretch.'),
    Exercise('Hammer curl', '3 × 10–12', 'Palms face each other the whole way.'),
  ],
  'Triceps': [
    Exercise('Close-grip bench press', '3 × 6–8', 'Hands shoulder-width, elbows tucked.'),
    Exercise('Rope pushdown', '3 × 10–12', 'Lock the elbows in place, spread the rope at the bottom.'),
    Exercise('Overhead triceps extension', '3 × 10–12', 'Lower behind the head for a deep stretch.'),
    Exercise('Dip', '3 × 8–12', 'Stay upright to keep the load on the triceps.'),
  ],
  'Forearms': [
    Exercise('Wrist curl', '3 × 15', 'Forearms resting on a bench, move only the wrists.'),
    Exercise('Reverse curl', '3 × 12', 'Overhand grip, slow on the way down.'),
    Exercise('Farmer carry', '3 × 30–40 m', 'Heavy dumbbells, stand tall, crush the handles.'),
  ],
  'Core': [
    Exercise('Plank', '3 × 45–60 s', 'Squeeze glutes and abs, hips level with shoulders.'),
    Exercise('Hanging leg raise', '3 × 10–12', 'No swinging; curl the hips up at the top.'),
    Exercise('Cable crunch', '3 × 12–15', 'Round the spine, bring elbows toward the knees.'),
    Exercise('Russian twist', '3 × 20', 'Rotate the chest, not only the arms.'),
  ],
  'Glutes': [
    Exercise('Hip thrust', '4 × 8–10', 'Chin tucked, pause and squeeze at the top.'),
    Exercise('Bulgarian split squat', '3 × 8–10 each leg', 'Lean forward slightly, push through the heel.'),
    Exercise('Cable kickback', '3 × 12–15 each leg', 'Small controlled range, no arching the back.'),
  ],
  'Quads': [
    Exercise('Squat', '4 × 5–8', 'Knees track over the toes, hips at least to knee level.'),
    Exercise('Leg press', '3 × 10–12', 'Feet lower on the plate, do not lock the knees.'),
    Exercise('Walking lunge', '3 × 10 each leg', 'Long steps, torso upright.'),
    Exercise('Leg extension', '3 × 12–15', 'Pause one second at the top.'),
  ],
  'Hamstrings': [
    Exercise('Romanian deadlift', '4 × 8', 'Push the hips back, bar close to the legs.'),
    Exercise('Lying leg curl', '3 × 10–12', 'Hips stay down on the pad.'),
    Exercise('Good morning', '3 × 10', 'Light bar, soft knees, hinge at the hips.'),
  ],
  'Calves': [
    Exercise('Standing calf raise', '4 × 10–12', 'Full stretch at the bottom, pause at the top.'),
    Exercise('Seated calf raise', '3 × 15', 'Slow reps, no bouncing.'),
  ],
};
