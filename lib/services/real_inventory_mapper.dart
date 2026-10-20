import '../models/inventory_item_model.dart';
import '../models/iot_models.dart';
import '../utils/constants.dart';

/// Builds the app's blood-bag records from what the VitaLink server knows
/// about a cold-chain device.
///
/// The server stores one row per bag: uid, blood group and expiry. Anything
/// it does not store (collection date, bag state, units) is either derived
/// with a documented rule or marked as unknown, so the UI can show a dash
/// instead of an invented value.
class RealInventoryMapper {
  RealInventoryMapper._();

  /// Shelf life used to estimate a collection date from the expiry date.
  static const int shelfLifeDays = 35;

  /// Builds one record per bag the device reported.
  static List<BloodBagModel> bags({
    required List<DeviceBag> deviceBags,
    IotDevice? device,
  }) {
    return deviceBags.map((b) => bag(b, device: device)).toList();
  }

  /// Maps a single server bag row onto the app's bag model.
  static BloodBagModel bag(DeviceBag source, {IotDevice? device}) {
    final expiry = source.expiry;
    final collection =
        expiry?.subtract(const Duration(days: shelfLifeDays));
    final temperature = device?.temperatureC;

    return BloodBagModel(
      bagId: source.uid,
      hospitalId: device?.hospitalId ?? '',
      // The server does not expose the hospital name, so it stays empty and
      // the UI hides the row instead of showing a made-up centre.
      hospitalName: '',
      bloodGroup: source.group,
      units: 1,
      rfidTag: source.uid,
      collectionDate: collection ?? DateTime.now(),
      expiryDate: expiry ?? DateTime.now(),
      status: BagStatus.stored,
      storageUnitName: device?.storageUnit ?? '',
      currentTempCelsius: temperature ?? 0,
      serverBacked: true,
      expiryKnown: expiry != null,
      collectionDateKnown: collection != null,
      collectionDateEstimated: collection != null,
      temperatureKnown: temperature != null,
    );
  }

  /// Units per blood group, including the groups that are not stocked.
  static Map<String, int> groupCounts(List<BloodBagModel> bags) {
    final counts = <String, int>{};
    for (final group in BloodConstants.groups) {
      counts[group] = 0;
    }
    for (final bag in bags) {
      counts[bag.bloodGroup] = (counts[bag.bloodGroup] ?? 0) + bag.units;
    }
    return counts;
  }

  /// Groups that are stocked but running low.
  ///
  /// A group with no bags at all is simply not stocked, which is different
  /// from a shortage, so it is not reported as low.
  static List<String> lowStockGroups(
    Map<String, int> counts, {
    int threshold = 3,
  }) {
    final low = <String>[];
    counts.forEach((group, count) {
      if (count > 0 && count < threshold) low.add(group);
    });
    return low;
  }
}
