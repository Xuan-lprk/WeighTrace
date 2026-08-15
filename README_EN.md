# AFU-WL Body Composition Scale for iOS

English | [简体中文](README.md)

An unofficial client built with SwiftUI and CoreBluetooth for reading selected AFU-WL / Welland body composition scales without connecting to Alibaba servers, with optional Apple Health integration.

> This project is based on community reverse-engineering research and is not affiliated with or authorized by Ant Afu, Welland, Fitdays, Icomon, or Apple.

This fork is based on [maoziban/smart-body-scale-IOS](https://github.com/maoziban/smart-body-scale-IOS) and preserves the original repository's Git history. It adds HealthKit writes, ADC selection, more reliable advertisement parsing, device identity binding, and clearer algorithm and privacy documentation.

## Current Features

- Scans for and connects to the verified `AFU-WL-TZ-A1` device with `subtype=7`.
- Displays live weight and saves one local record after the measurement stabilizes.
- Preserves both ADC values sent by the scale and lets you select ADC 1 or ADC 2 for estimation.
- Estimates body fat from weight and impedance, then displays additional metrics derived proportionally from body fat.
- Supports a personal profile, household member matching, and local measurement history.
- Optionally writes the following data to Apple Health:
  - Weight
  - BMI
  - Body fat percentage
  - Lean body mass
- Reads body measurement records from the past year in Apple Health and identifies their source apps.
- Flags potentially duplicate weights written by different apps within a short period, without deleting anything automatically.
- Contains no accounts, ads, network requests, or third-party analytics SDKs.
- Supports Simplified Chinese and English and automatically follows the system language.

## Where the Data Comes From

| Data | Source | Meaning |
|---|---|---|
| Weight | Measured directly by the scale | Parsed from BLE packets |
| ADC 1 / ADC 2 | Sent directly by the scale | Their exact physical meaning has not been fully confirmed |
| Impedance | Protocol conversion | Derived from the selected ADC value |
| BMI | Calculated locally | Weight divided by height squared |
| Body fat percentage | Estimated locally with a BIA formula | Not an official body fat field returned by the scale |
| Water, muscle, bone mass, protein, and subcutaneous fat | Roughly derived locally | Must not be treated as independent measurements |

The current primary BIA formula is based on the body composition estimation equations published by Segal et al. in 1988. The study population consisted mainly of adults, so results for children and adolescents require particular caution. When no valid impedance is available, the app falls back to an estimate based on BMI, age, and sex.

Formula references:

- Segal KR et al. (1988), [Lean body mass estimation by bioelectrical impedance analysis: a four-site cross-validation study](https://pubmed.ncbi.nlm.nih.gov/3337041/)
- Deurenberg P et al. (1991), [Body mass index as a measure of body fatness: age- and sex-specific prediction formulas](https://doi.org/10.1079/BJN19910073)

## Accuracy and Limitations

Weight is measured directly by the scale, and the ADC values are sent directly by the scale. Impedance is derived through protocol conversion. Body fat, water, muscle, bone mass, and other body composition values are local formula estimates and must not replace medical examinations.

Ant Afu's body composition results are also consumer-grade estimates. You can switch between ADC 1 and ADC 2 to reduce the difference from the official results, but being closer to the official result does not mean being medically more accurate. That said, selecting the ADC with the smaller difference is still recommended, since Alibaba's result may be closer to the actual value.

For long-term trend tracking, use the same ADC consistently and measure under similar conditions.

## Verified Hardware

- Advertisement name: `AFU-WL-TZ-A1`
- Category: `2`
- Subtype: `7`
- Service: `FFB0`
- Notify characteristic: `FFB2`

Other models and firmware versions may use different advertisements or packet formats. See the [protocol notes](docs/PROTOCOL.md) for detailed reverse-engineering findings.

## Requirements

- Xcode 16 or later
- iOS / iPadOS 16.6 or later
- A physical iPhone or iPad with Bluetooth Low Energy support
- A personal or paid Apple Developer team with HealthKit enabled if you want to write to Apple Health

The simulator can be used to compile the project and inspect the interface, but it cannot perform real Bluetooth measurements.

## Running the App

1. Clone the repository and open `体脂秤.xcodeproj`.
2. Select the app target and choose your own team under **Signing & Capabilities**.
3. If necessary, change the Bundle Identifier to a unique identifier that you own.
4. Connect an iPhone or iPad and run the app.
5. Fully quit Ant Afu on other devices. If the scale is still occupied, turn off Bluetooth on those devices. Do not turn off Bluetooth on the iPhone or iPad running this app.
6. Step onto the scale barefoot to wake it, then select the discovered device on the pairing screen.

If the scale does not appear, check the following:

- Bluetooth access is enabled for this app in system settings.
- The vendor app, another phone, and the desktop CLI are not connected to the scale.
- The scale's display is on and the scale is close to the device.
- The advertisement name and subtype match the verified hardware listed above.

## Apple Health

Open **Profile → Apple Health** to enable synchronization and select the metrics to write. The app automatically writes only new live measurements assigned to the primary user. It does not upload existing history or household member records in bulk.

Weight is a direct measurement. BMI, body fat percentage, and lean body mass include local calculations. HealthKit samples contain metadata such as the algorithm version, impedance, and ADC index for future traceability.

Open **Profile → Cross-Scale Data** to authorize reading weight, BMI, body fat percentage, and lean body mass and to see which app created each record. A record is considered a possible duplicate when different sources write weights within five minutes and the values differ by no more than 0.1 kg. Detection is informational only and never modifies Apple Health data.

## Privacy

The app itself makes no network requests. Profiles and measurement history remain in the app sandbox. When Apple Health integration is enabled, selected data is passed to HealthKit; whether it syncs through iCloud depends on the user's system settings. See [PRIVACY.md](docs/PRIVACY.md) for the complete statement.

Before sharing issues or logs publicly, remove names, dates of birth, weights, and Bluetooth device identifiers.

## Project Structure

```text
体脂秤/
├── App/                    # App entry point and root view
├── Models/                 # Measurement, member, and ADC comparison models
├── Services/               # Bluetooth, HealthKit, profiles, algorithms, and OCR
├── Views/                  # SwiftUI feature screens and shared components
├── Assets.xcassets/        # App icons and color assets
└── 体脂秤.entitlements      # HealthKit entitlement
docs/
├── PRIVACY.md              # Privacy statement
└── PROTOCOL.md             # AFU-WL reverse-engineering notes
```

## Build Check

```bash
xcodebuild \
  -project "体脂秤.xcodeproj" \
  -scheme "体脂秤" \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions runs the same unsigned build on every push and pull request.

## Contributing

Compatibility fixes and sanitized protocol samples are welcome. Please avoid:

- Committing real health data, device UUIDs, or Apple Developer team information.
- Describing estimated metrics as medical measurements.
- Changing production formulas or the default ADC without comparison data.

## License

This fork was created with permission from the upstream author and is released under the [GNU General Public License v3.0](LICENSE).
