#  GrowWiser

**GrowWiser** is an IoT-powered smart irrigation system designed to automate and monitor plant care in real time. Built as a solo final-year project, it combines an ESP32 microcontroller with a Flutter mobile app to give users full visibility and control over their growing environment — anywhere, anytime.

---

##  Features

- **Real-time sensor monitoring** — soil moisture, temperature, and humidity streamed live to the app
- **Automated pump control** — relay-triggered irrigation based on sensor thresholds
- **QR-based device claiming** — scan the OLED-displayed QR code to link a device to your account instantly
- **Role-based access** — separate views and permissions for regular users and admins
- **Error logging pipeline** — device errors routed through MQTT and stored in Firestore for admin review
- **Cross-platform mobile app** — Flutter app targeting Android and iOS (sideloaded)
- **CI/CD pipeline** — automated builds and checks via GitHub Actions

---

##  Architecture

```
┌─────────────────────────────────────────────────────┐
│                   Flutter App                       │
│         (Riverpod + BackendService singleton)       │
└────────────┬────────────────────────┬───────────────┘
             │ Firebase Auth          │ Firestore / RTDB
             ▼                        ▼
┌────────────────────┐    ┌───────────────────────────┐
│   Firebase Auth    │    │  Firebase Firestore        │
│   (Phone OTP)      │    │  - Device metadata         │
└────────────────────┘    │  - User ownership tokens   │
                          │  - Error logs              │
                          └──────────────┬────────────┘
                                         │
                          ┌──────────────▼────────────┐
                          │  Firebase Realtime DB      │
                          │  - Live sensor readings    │
                          │  - UserDevices mirror      │
                          └──────────────┬────────────┘
                                         │ MQTT
                          ┌──────────────▼────────────┐
                          │   Mosquitto MQTT Broker    │
                          └──────────────┬────────────┘
                                         │
                          ┌──────────────▼────────────┐
                          │         ESP32              │
                          │  - DHT22 (temp/humidity)  │
                          │  - Soil moisture sensor    │
                          │  - Relay (pump control)    │
                          │  - SSD1306 OLED (QR code) │
                          └───────────────────────────┘
```

---

##  Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter, Dart |
| State Management | Riverpod |
| Authentication | Firebase Phone Auth |
| Cloud Database | Firebase Firestore |
| Realtime Data | Firebase Realtime Database |
| Messaging | MQTT (Mosquitto broker) |
| Microcontroller | ESP32 |
| Sensors | DHT22, capacitive soil moisture |
| Actuator | 5V relay module + water pump |
| Display | SSD1306 OLED (128×64, I2C) |
| CI/CD | GitHub Actions |
| Design | Figma |

---

##  App Pages

- **Login / Register** — Phone OTP authentication with PageView slide transition
- **Dashboard** — Live arc gauge for soil moisture, temperature, and humidity cards
- **Devices** — List of claimed devices, QR-based device onboarding
- **Command** — Manual pump toggle and irrigation scheduling
- **Admin Panel** — Error log viewer via collectionGroup queries

---

##  Hardware Wiring

| Component | GPIO |
|---|---|
| DHT22 (data) | GPIO 4 |
| Soil moisture (analog) | GPIO 34 |
| Relay (IN) | GPIO 26 |
| OLED SDA | GPIO 21 |
| OLED SCL | GPIO 22 |

> **Note:** Relay VCC is wired to the **3.3V rail**, not VIN. The relay module is active-LOW — `LOW` signal activates the pump.

---

##  Getting Started

### Prerequisites

- Flutter SDK ≥ 3.x
- Firebase project with Firestore, Realtime Database, and Phone Auth enabled
- MQTT broker (Mosquitto) running and accessible
- Arduino IDE or PlatformIO for ESP32 firmware

### Firebase Setup

1. Create a Firebase project and enable **Phone Authentication**, **Firestore**, and **Realtime Database**
2. Download `google-services.json` (Android) and `GoogleService-Info.plist` (iOS) and place them in the respective platform directories
3. Set up Firestore security rules so users can only access their own device data

### Flutter App

```bash
git clone https://github.com/<your-username>/growwiser.git
cd growwiser
flutter pub get
flutter run
```

### ESP32 Firmware

1. Open the firmware project in Arduino IDE or PlatformIO
2. Update `config.h` with your Wi-Fi credentials and MQTT broker address
3. Flash to the ESP32 board

---

##  Firestore Security Rules

Devices and sensor data are scoped per user. Users can only read and write their own documents. Admins have elevated access for error log review via a dedicated collection group.

---

##  Project Structure

```
growwiser/
├── lib/
│   ├── main.dart
│   ├── app_theme.dart
│   ├── services/
│   │   └── backend_service.dart       # Singleton for Firebase + MQTT
│   ├── providers/                     # Riverpod providers
│   ├── pages/
│   │   ├── login_page.dart
│   │   ├── dashboard_page.dart
│   │   ├── devices_page.dart
│   │   ├── command_page.dart
│   │   └── admin_page.dart
│   └── widgets/
│       ├── growwiser_navbar.dart
│       └── arc_gauge_painter.dart     # CustomPainter for soil moisture gauge
├── firmware/                          # ESP32 Arduino sketch
│   ├── growwiser_firmware.ino
│   └── config.h
├── .github/
│   └── workflows/
│       └── ci.yml                     # GitHub Actions CI/CD
└── README.md
```

---

##  Testing

GrowWiser was validated through multiple testing strategies covering unit behaviour, system integration, user acceptance, and interaction flows — conducted on physical hardware and the production Flutter app during the final FYP exhibition.

---

### Unit Testing

Unit tests focused on isolating core logic within the Flutter app, verifying that individual functions behaved correctly independent of Firebase or hardware dependencies.

| Test | Description | Result |
|---|---|---|
| UT-01 | Soil moisture percentage calculation from raw ADC value | ✅ Pass |
| UT-02 | Device ID generation from ESP32 MAC address | ✅ Pass |
| UT-03 | Token validation logic for device claiming | ✅ Pass |
| UT-04 | MQTT topic string construction per device | ✅ Pass |
| UT-05 | Sensor threshold comparison for pump trigger condition | ✅ Pass |

---

### Integration Testing

Integration tests verified end-to-end data flow across the full system stack — from ESP32 firmware publishing over MQTT, through Firebase ingestion, to Flutter UI rendering.

| ID | Test Case | Result |
|---|---|---|
| TC-01 | Device claiming via QR code scan | ✅ Pass |
| TC-02 | Real-time sensor data streaming to dashboard | ✅ Pass |
| TC-03 | Manual pump activation via app command | ✅ Pass |
| TC-04 | Error event logging to Firestore and admin panel display | ✅ Pass |
| TC-05 | Multi-user data isolation (users cannot access other users' devices) | ✅ Pass |

The relay and pump were tested live on breadboard hardware, confirming correct active-LOW behavior and accurate soil moisture threshold triggering. Minor issues identified during development — relay VCC wiring, iOS sideload crash in debug mode, Firestore security rule mismatches — were all resolved prior to the exhibition.

---

### Interaction Testing

Interaction testing evaluated the usability and responsiveness of the Flutter app UI, focusing on navigation flows, real-time feedback, and edge-case user behaviour.

| ID | Scenario | Expected Behaviour | Result |
|---|---|---|---|
| IT-01 | User logs in with valid phone OTP | Redirected to dashboard, devices loaded | ✅ Pass |
| IT-02 | User scans QR code on OLED display | Device claimed and appears in device list | ✅ Pass |
| IT-03 | Dashboard opened with no active device | Empty state shown, no crash | ✅ Pass |
| IT-04 | Pump toggled while sensor data is streaming | Command sent without interrupting live feed | ✅ Pass |
| IT-05 | Admin navigates to error log panel | Logs fetched via collectionGroup and rendered correctly | ✅ Pass |
| IT-06 | User attempts to access another user's device data | Request blocked by Firestore security rules | ✅ Pass |

---

### User Acceptance Testing (UAT)

UAT was conducted with a small group of end users during the FYP exhibition, assessing whether GrowWiser met real-world usability expectations without technical guidance.

| Criteria | Feedback |
|---|---|
| Device onboarding (QR scan to claim) | Users found the process intuitive and fast |
| Dashboard readability | Sensor values and gauge were clear at a glance |
| Pump control responsiveness | Users noted near-instant feedback after toggling |
| App stability during demo | No crashes observed across multiple test sessions |
| Overall satisfaction | Positive — GrowWiser was awarded **Best Booth** at the FYP exhibition |

---

##  Author

**Shar**
Diploma in Computer Science — Universiti Malaysia Pahang Al-Sultan Abdullah (UMPSA)
Final Year Project, 2026

---

##  License

This project is for academic purposes. All rights reserved.
