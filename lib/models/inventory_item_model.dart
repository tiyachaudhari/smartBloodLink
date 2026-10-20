import '../utils/constants.dart';

/// Hospital blood bag inventory item with RFID tracking
class BloodBagModel {
  final String bagId;
  final String hospitalId;
  final String hospitalName;
  final String bloodGroup;
  final int units;
  final String rfidTag;
  final DateTime collectionDate;
  final DateTime expiryDate;
  final BagStatus status;
  final String storageUnitName;
  final double currentTempCelsius;
  final String? reservedForRequestId;
  final String? notes;

  /// True when the record came from the VitaLink server rather than the
  /// bundled simulation. Server-backed records never show invented values.
  final bool serverBacked;

  /// False when the server did not send an expiry date. The UI shows a dash
  /// instead of a made-up date.
  final bool expiryKnown;

  /// False when no collection date could be derived from the expiry date.
  final bool collectionDateKnown;

  /// True when the collection date was derived from the expiry date rather
  /// than reported by the server.
  final bool collectionDateEstimated;

  /// False when the device did not report a temperature for this bag.
  final bool temperatureKnown;

  BloodBagModel({
    required this.bagId,
    required this.hospitalId,
    required this.hospitalName,
    required this.bloodGroup,
    this.units = 1,
    required this.rfidTag,
    required this.collectionDate,
    required this.expiryDate,
    this.status = BagStatus.stored,
    this.storageUnitName = 'Cold Storage Fridge A',
    this.currentTempCelsius = 4.2,
    this.reservedForRequestId,
    this.notes,
    this.serverBacked = false,
    this.expiryKnown = true,
    this.collectionDateKnown = true,
    this.collectionDateEstimated = false,
    this.temperatureKnown = true,
  });

  bool get isExpired => DateTime.now().isAfter(expiryDate);

  int get daysUntilExpiry => expiryDate.difference(DateTime.now()).inDays;

  factory BloodBagModel.fromMap(Map<String, dynamic> map, String id) {
    return BloodBagModel(
      bagId: id,
      hospitalId: map['hospitalId'] ?? '',
      hospitalName: map['hospitalName'] ?? 'General Blood Bank',
      bloodGroup: map['bloodGroup'] ?? 'O+',
      units: map['units'] ?? 1,
      rfidTag: map['rfidTag'] ?? map['rfid'] ?? 'RFID-UNKNOWN',
      collectionDate: map['collectionDate'] != null
          ? DateTime.tryParse(map['collectionDate']) ?? DateTime.now()
          : DateTime.now(),
      expiryDate: map['expiryDate'] != null
          ? DateTime.tryParse(map['expiryDate']) ??
              DateTime.now().add(const Duration(days: 35))
          : DateTime.now().add(const Duration(days: 35)),
      status: BagStatus.values.firstWhere(
        (s) => s.name == (map['status'] ?? 'stored').toString().toLowerCase(),
        orElse: () => BagStatus.stored,
      ),
      storageUnitName: map['storageUnitName'] ?? 'Cold Storage Fridge A',
      currentTempCelsius:
          (map['currentTempCelsius'] as num?)?.toDouble() ?? 4.2,
      reservedForRequestId: map['reservedForRequestId'],
      notes: map['notes'],
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'bagId': bagId,
      'hospitalId': hospitalId,
      'hospitalName': hospitalName,
      'bloodGroup': bloodGroup,
      'units': units,
      'rfidTag': rfidTag,
      'collectionDate': collectionDate.toIso8601String(),
      'expiryDate': expiryDate.toIso8601String(),
      'status': status.name,
      'storageUnitName': storageUnitName,
      'currentTempCelsius': currentTempCelsius,
      'reservedForRequestId': reservedForRequestId,
      'notes': notes,
    };
  }

  BloodBagModel copyWith({
    BagStatus? status,
    String? storageUnitName,
    double? currentTempCelsius,
    String? reservedForRequestId,
    String? notes,
  }) {
    return BloodBagModel(
      bagId: bagId,
      hospitalId: hospitalId,
      hospitalName: hospitalName,
      bloodGroup: bloodGroup,
      units: units,
      rfidTag: rfidTag,
      collectionDate: collectionDate,
      expiryDate: expiryDate,
      status: status ?? this.status,
      storageUnitName: storageUnitName ?? this.storageUnitName,
      currentTempCelsius: currentTempCelsius ?? this.currentTempCelsius,
      reservedForRequestId: reservedForRequestId ?? this.reservedForRequestId,
      notes: notes ?? this.notes,
      serverBacked: serverBacked,
      expiryKnown: expiryKnown,
      collectionDateKnown: collectionDateKnown,
      collectionDateEstimated: collectionDateEstimated,
      temperatureKnown: temperatureKnown,
    );
  }
}
