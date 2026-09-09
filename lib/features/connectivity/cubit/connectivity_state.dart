import 'package:equatable/equatable.dart';

class ConnectivityStatus extends Equatable {
  /// `true` when there is no internet connection.
  final bool offline;

  const ConnectivityStatus({required this.offline});

  @override
  List<Object?> get props => [offline];
}