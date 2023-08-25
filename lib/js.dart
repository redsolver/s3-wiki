@JS()
library callable_function;

import 'package:js/js.dart';

/// Allows assigning a function to be callable from `window.clickjs()`
@JS('clickjs')
external set clickJS(void Function(String type, String id) f);
