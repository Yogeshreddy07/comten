import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/theme/app_theme.dart';
import 'package:frontend/features/dashboard/model/dashboard_item.dart';
import 'package:frontend/features/dashboard/widgets/dashboard_card.dart';

void main(){
 for(final width in [320.0,360.0,390.0]){
  for(final scale in [1.0,1.3,2.0]){
   testWidgets('Dashboard cards fit width $width text scale $scale',(tester) async{
    final entry=DashboardModuleEntry(DashboardModule.employees);
    final cardWidth=(width-56)/2;
    await tester.pumpWidget(MaterialApp(theme:AppTheme.lightTheme,home:MediaQuery(
     data:MediaQueryData(textScaler:TextScaler.linear(scale)),
     child:Builder(builder:(context)=>Scaffold(body:Align(alignment:Alignment.topLeft,
      child:SizedBox(width:cardWidth,height:DashboardModuleCard.gridHeight(context,[entry],cardWidth),
       child:DashboardModuleCard(entry:entry,onTap:(){}))))),
    )));
    expect(tester.takeException(),isNull);
    expect(find.text(entry.title),findsOneWidget);
    expect(find.text(entry.description),findsOneWidget);
   });
  }
 }
}
