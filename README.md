# Auto Levels (Proxy) — Flutter (Android)

This repository contains the *app code* (lib/ + pubspec.yaml) for an Android Flutter app that:
- pulls daily OHLC data for:
  - **NQ.F** (Nasdaq 100 E-mini future proxy) from Stooq
  - **XAUUSD** (Gold spot proxy) from Stooq
  - **Bitcoin** from CoinGecko
- computes:
  - **Daily (last complete daily candle)** High/Low
  - **Weekly (previous ISO week)** High/Low
  - **YTD (since Jan 1 of current year)** High/Low
- shows all values (High/Low + dates + current price + timestamps) + a visual "range position" bar and buy/neutral/sell badges.

## Data sources used by the app
- Stooq pages include historical data download in CSV format, e.g. XAUUSD: https://stooq.com/q/d/?s=xauusd
- Stooq NQ.F quote page: https://stooq.pl/q/?s=nq.f
- CoinGecko endpoint showcase mentions /coins/{id}/ohlc and /simple/price: https://docs.coingecko.com/docs/endpoint-showcase

## How to build an APK (Android)
1) Install Flutter: https://docs.flutter.dev/get-started/install
2) Create a new project, then copy these files over:
   - `pubspec.yaml`
   - `lib/` folder
3) Run:
   - `flutter pub get`
   - `flutter run`  (debug on device)
   - `flutter build apk --release`  (release APK)
Flutter Android release docs: https://docs.flutter.dev/deployment/android

## Notes
- If CoinGecko blocks the public `/ohlc` endpoint without a key, the app will show Bitcoin as "data source error".
  In that case you can later switch the BTC data source to a paid plan (or manual input).
