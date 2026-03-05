import 'package:omi/backend/schema/bt_device/bt_device.dart';
import 'package:omi/backend/schema/conversation.dart';
import 'package:omi/services/wals/wal.dart';
import 'package:omi/services/wals/wal_interfaces.dart';

/// No-op flash page sync for the glasses-only MVP.
///
/// Legacy Limitless flash-page transfer is intentionally disabled, but this
/// keeps the sync orchestration API stable for the rest of the app.
class FlashPageWalSyncImpl implements FlashPageWalSync {
  final IWalSyncListener listener;

  LocalWalSync? _localSync;

  FlashPageWalSyncImpl(this.listener);

  @override
  bool get isSyncing => false;

  @override
  void setLocalSync(LocalWalSync localSync) {
    _localSync = localSync;
  }

  @override
  void setDevice(BtDevice? device) {
    listener.onWalUpdated();
  }

  @override
  Future<void> deleteAllSyncedWals() async {}

  @override
  Future<void> deleteWal(Wal wal) async {
    listener.onWalUpdated();
  }

  @override
  Future<List<Wal>> getMissingWals() async {
    return const [];
  }

  @override
  Future<SyncLocalFilesResponse?> syncAll({
    IWalSyncProgressListener? progress,
    IWifiConnectionListener? connectionListener,
  }) async {
    return null;
  }

  @override
  Future<SyncLocalFilesResponse?> syncWal({
    required Wal wal,
    IWalSyncProgressListener? progress,
    IWifiConnectionListener? connectionListener,
  }) async {
    return null;
  }

  @override
  Future<void> start() async {
    if (_localSync != null) {
      listener.onWalUpdated();
    }
  }

  @override
  Future<void> stop() async {}

  @override
  void cancelSync() {}
}
