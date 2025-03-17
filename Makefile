run: 
	flutter run

apk: clean pub icon
	flutter build apk --split-per-abi

linux: clean pub icon
	flutter build linux --release

icon:
	flutter pub run flutter_launcher_icons

clean:
	flutter clean

pub:
	flutter pub get
