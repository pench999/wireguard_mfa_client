import 'dart:io';

import 'package:flutter/widgets.dart';

bool get canPollAuthentication =>
    !Platform.isAndroid ||
    WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
