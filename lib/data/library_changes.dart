import 'package:flutter/foundation.dart';

class LibraryChanges extends ChangeNotifier {
  static final instance = LibraryChanges();
  void changed() => notifyListeners();
}
