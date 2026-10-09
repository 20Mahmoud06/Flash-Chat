import 'package:flutter/material.dart';
import 'package:equatable/equatable.dart';

class ThemeState extends Equatable {
  final ThemeMode mode;

  const ThemeState(this.mode);

  @override
  List<Object?> get props => [mode];
}