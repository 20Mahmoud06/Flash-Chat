import 'package:bloc/bloc.dart';
import 'package:flash_chat_app/services/connectivity/connectivity_service.dart';
import 'connectivity_state.dart';

/// Exposes the global connectivity status to the UI so it can show a nice
/// in-app banner when the connection is lost and when it comes back.
class ConnectivityCubit extends Cubit<ConnectivityStatus> {
  ConnectivityCubit()
      : super(const ConnectivityStatus(offline: false)) {
    ConnectivityService.instance.isConnected.addListener(_sync);
    _sync();
  }

  void _sync() {
    final offline = !ConnectivityService.instance.isConnected.value;
    if (!isClosed && state.offline != offline) {
      emit(ConnectivityStatus(offline: offline));
    }
  }

  @override
  Future<void> close() {
    ConnectivityService.instance.isConnected.removeListener(_sync);
    return super.close();
  }
}