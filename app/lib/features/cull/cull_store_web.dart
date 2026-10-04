import 'package:lumen/features/cull/cull_store.dart';

/// Web demo: the cull cache lives in memory.
Future<CullStore> openCullStore() async => MemoryCullStore();
