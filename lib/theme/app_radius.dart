import 'package:flutter/material.dart';

abstract final class AppRadius {
  static const sm = 10.0;
  static const md = 14.0;
  static const lg = 16.0;
  static const xl = 18.0;

  static BorderRadius get button => BorderRadius.circular(xl);
  static BorderRadius get card => BorderRadius.circular(lg);
  static BorderRadius get input => BorderRadius.circular(md);
  static BorderRadius get chip => BorderRadius.circular(sm);
}
