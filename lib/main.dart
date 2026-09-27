import 'package:flutter/widgets.dart';

import 'app.dart';
import 'app_services.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.create(args: args);
  runApp(MdViewerApp(services: services));
}
