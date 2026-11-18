// Temporary: draws the body figure large, to check the drawing. Deleted once it looks right.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:personal_mobile_app/body_map.dart';
import 'package:personal_mobile_app/theme.dart';

void main() {
  testWidgets('figure', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final colors = AppColors.of(palettes.first, Brightness.dark);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [colors]),
        home: Container(
          color: colors.surface,
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            spacing: 20,
            children: [
              BodyMap(side: 'front', selected: 'Chest', stale: const ['Quads'], onSelect: (_) {}, height: 860),
              BodyMap(
                side: 'back',
                selected: 'Back',
                stale: const [],
                planned: const {'Glutes'},
                onSelect: (_) {},
                height: 860,
              ),
              const BodyFigure(side: 'front', lit: {'Chest', 'Shoulders'}, height: 90),
              const BodyFigure(side: 'back', lit: {'Back'}, height: 90),
            ],
          ),
        ),
      ),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('preview/_figure.png'));
  });
}
