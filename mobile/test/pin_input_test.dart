import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/shared/widgets/pin_code_input.dart';

void main() {
  testWidgets('PIN remains secure and keyboard-accessible through transparent input',(tester) async {
    final controller=TextEditingController();
    final semantics=tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:PinCodeInput(controller:controller))));
    await tester.pumpAndSettle();
    bool secureField=false;
    void inspect(SemanticsNode node) {
      final data=node.getSemanticsData();
      if(data.flagsCollection.isTextField && data.flagsCollection.isObscured) secureField=true;
      node.visitChildren((child){inspect(child);return true;});
    }
    tester.binding.rootPipelineOwner.visitChildren((owner) {
      final root=owner.semanticsOwner?.rootSemanticsNode;
      if(root!=null) inspect(root);
    });
    expect(secureField,isTrue);
    await tester.enterText(find.byType(TextField),'1234');await tester.pump();
    expect(controller.text,'1234');
    expect(find.byWidgetPredicate((widget)=>widget is Text && widget.data=='1234'),findsNothing);
    semantics.dispose();
    await tester.pumpWidget(const SizedBox());controller.dispose();
  });
}
