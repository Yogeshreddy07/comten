import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/shared/widgets/pin_code_input.dart';

void main() {
  testWidgets('tapping PIN dots reopens keyboard after Android Back hides it', (tester) async {
    final controller=TextEditingController();
    await tester.pumpWidget(MaterialApp(home:Scaffold(body:PinCodeInput(controller:controller,autofocus:true))));
    await tester.pump(const Duration(milliseconds:300));
    final field=tester.widget<TextField>(find.byType(TextField));
    expect(field.focusNode!.hasFocus,isTrue);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    field.focusNode!.requestFocus();
    await tester.pump();
    // Android can hide its IME while keeping the Flutter focus node focused.
    tester.testTextInput.hide();
    tester.testTextInput.log.clear();
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pump();
    expect(tester.testTextInput.log.any((m)=>m.method=='TextInput.show'),isTrue);
    await tester.pumpWidget(const SizedBox());controller.dispose();
  });
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
