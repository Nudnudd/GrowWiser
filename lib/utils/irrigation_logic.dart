enum IrrigationMode {
  autoIrrigate,    // moisture < lowerThreshold → system irrigates automatically
  manualUnlocked,  // lowerThreshold ≤ moisture ≤ upperThreshold → manual allowed
  blocked,         // moisture > upperThreshold → irrigation blocked
}

class IrrigationLogic {
  static IrrigationMode evaluate({
    required double moisture,
    required double lowerThreshold,  // default 50
    required double upperThreshold,  // default 80
  }) {
    if (moisture < lowerThreshold) return IrrigationMode.autoIrrigate;
    if (moisture <= upperThreshold) return IrrigationMode.manualUnlocked;
    return IrrigationMode.blocked;
  }
}