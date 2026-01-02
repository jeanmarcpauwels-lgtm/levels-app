import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const InvestApp());
}

class InvestApp extends StatelessWidget {
  const InvestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Invest',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        colorSchemeSeed: Colors.blue,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: Colors.blue,
      ),
      home: const DashboardScreen(),
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final List<Asset> _defaultAssets = const [
    Asset.stooq(
      title: 'Nasdaq 100 Future (proxy)',
      symbol: 'nq.f',
      displaySymbol: 'NQ.F',
      unit: '',
    ),
    Asset.coingecko(
      title: 'Bitcoin',
      coinId: 'bitcoin',
      displaySymbol: 'BTC',
      vsCurrency: 'usd',
      unit: r'$',
    ),
    Asset.stooq(
      title: 'Gold spot (proxy)',
      symbol: 'xauusd',
      displaySymbol: 'XAUUSD',
      unit: r'$',
    ),
  ];

  List<Asset> assets = [];
  late Future<List<AssetSnapshot>> _snapshots;

  static const String _prefsKey = 'assets_v1';

  @override
  void initState() {
    super.initState();
    _snapshots = _bootstrap();
  }

  Future<List<AssetSnapshot>> _bootstrap() async {
    assets = await _loadAssetsFromPrefs() ?? List<Asset>.from(_defaultAssets);
    return _loadAll();
  }

  Future<List<AssetSnapshot>> _loadAll() async {
    final results = <AssetSnapshot>[];
    for (final a in assets) {
      // Small pacing to reduce CoinGecko 429 risk.
      if (results.isNotEmpty) {
        await Future.delayed(const Duration(milliseconds: 350));
      }
      results.add(await a.fetchAndCompute());
    }
    return results;
  }

  Future<void> _refresh() async {
    setState(() => _snapshots = _loadAll());
  }

  Future<void> _removeAssetByKey(String assetKey) async {
    setState(() {
      assets.removeWhere((a) => a.key == assetKey);
      _snapshots = _loadAll();
    });
    await _saveAssetsToPrefs(assets);
  }

  Future<void> _confirmAndRemove(String assetKey, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Delete'),
        content: Text('Remove "$label" ?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _removeAssetByKey(assetKey);
    }
  }

  Future<void> _saveAssetsToPrefs(List<Asset> assets) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = assets.map((a) => a.toJson()).toList();
    await prefs.setString(_prefsKey, jsonEncode(payload));
  }

  Future<List<Asset>?> _loadAssetsFromPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) return null;

    final decoded = jsonDecode(raw);
    if (decoded is! List) return null;

    final list = <Asset>[];
    for (final e in decoded) {
      if (e is Map<String, dynamic>) {
        final a = Asset.fromJson(e);
        if (a != null) list.add(a);
      } else if (e is Map) {
        final map = e.map((k, v) => MapEntry(k.toString(), v));
        final a = Asset.fromJson(map);
        if (a != null) list.add(a);
      }
    }
    return list.isEmpty ? null : list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Invest'),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final added = await showModalBottomSheet<Asset>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (context) {
              return SafeArea(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                  ),
                  child: const AddAssetSheet(),
                ),
              );
            },
          );

          if (added != null) {
            setState(() {
              // Avoid duplicates by key.
              assets.removeWhere((a) => a.key == added.key);
              assets = [...assets, added];
              _snapshots = _loadAll();
            });
            await _saveAssetsToPrefs(assets);
          }
        },
        child: const Icon(Icons.add),
      ),
      body: FutureBuilder<List<AssetSnapshot>>(
        future: _snapshots,
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Error: ${snap.error}'),
              ),
            );
          }

          final data = snap.data ?? [];
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.all(12),
              children: [
                for (final s in data)
                  AssetCard(
                    snapshot: s,
                    onDelete: () => _confirmAndRemove(
                      s.assetKey,
                      '${s.symbol} - ${s.title}',
                    ),
                  ),
                const SizedBox(height: 24),
                const _Footnote(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote();

  @override
  Widget build(BuildContext context) {
    final textStyle = Theme.of(context).textTheme.bodySmall;
    return Opacity(
      opacity: 0.8,
      child: Text(
        'Free proxies (Stooq + CoinGecko). Data is not broker-grade.\n'
        'Daily = last complete daily candle. Weekly = previous ISO week. YTD = since Jan 1.',
        style: textStyle,
      ),
    );
  }
}

enum AssetSource { stooq, coingecko }

class Asset {
  final AssetSource source;

  // Stooq
  final String? stooqSymbol;

  // CoinGecko
  final String? coinId;
  final String? vsCurrency;

  final String title;
  final String displaySymbol;
  final String unit;

  const Asset._({
    required this.source,
    required this.title,
    required this.displaySymbol,
    required this.unit,
    this.stooqSymbol,
    this.coinId,
    this.vsCurrency,
  });

  const Asset.stooq({
    required String title,
    required String symbol,
    required String displaySymbol,
    required String unit,
  }) : this._(
          source: AssetSource.stooq,
          title: title,
          stooqSymbol: symbol,
          displaySymbol: displaySymbol,
          unit: unit,
        );

  const Asset.coingecko({
    required String title,
    required String coinId,
    required String displaySymbol,
    required String vsCurrency,
    required String unit,
  }) : this._(
          source: AssetSource.coingecko,
          title: title,
          coinId: coinId,
          vsCurrency: vsCurrency,
          displaySymbol: displaySymbol,
          unit: unit,
        );

  String get key {
    if (source == AssetSource.stooq) {
      return 'stooq:${(stooqSymbol ?? '').toLowerCase()}|${displaySymbol.toUpperCase()}';
    }
    return 'cg:${(coinId ?? '').toLowerCase()}|${(vsCurrency ?? '').toLowerCase()}|${displaySymbol.toUpperCase()}';
  }

  Map<String, dynamic> toJson() {
    return {
      'source': source.name,
      'stooqSymbol': stooqSymbol,
      'coinId': coinId,
      'vsCurrency': vsCurrency,
      'title': title,
      'displaySymbol': displaySymbol,
      'unit': unit,
    };
  }

  static Asset? fromJson(Map<String, dynamic> m) {
    final sourceStr = (m['source'] as String?) ?? '';
    final title = (m['title'] as String?) ?? '';
    final displaySymbol = (m['displaySymbol'] as String?) ?? '';
    final unit = (m['unit'] as String?) ?? '';
    if (title.isEmpty || displaySymbol.isEmpty) return null;

    if (sourceStr == AssetSource.stooq.name) {
      final sym = (m['stooqSymbol'] as String?) ?? '';
      if (sym.isEmpty) return null;
      return Asset.stooq(
        title: title,
        symbol: sym,
        displaySymbol: displaySymbol,
        unit: unit,
      );
    }

    if (sourceStr == AssetSource.coingecko.name) {
      final id = (m['coinId'] as String?) ?? '';
      final vs = (m['vsCurrency'] as String?) ?? 'usd';
      if (id.isEmpty) return null;
      return Asset.coingecko(
        title: title,
        coinId: id,
        displaySymbol: displaySymbol,
        vsCurrency: vs,
        unit: unit,
      );
    }

    return null;
  }

  Future<AssetSnapshot> fetchAndCompute() async {
    try {
      if (source == AssetSource.stooq) {
        // Extra robust retries for NQ.F issue (empty body, transient blocking).
        final candles = await _fetchStooqDailyCandlesWithRetry(stooqSymbol!);
        final current = candles.last.close;
        final now = DateTime.now().toUtc();

        final levels = computeLevelsFromDaily(
          candles: candles,
          currentPrice: current,
          currentTimestampUtc: now,
        );

        return AssetSnapshot(
          assetKey: key,
          title: title,
          symbol: displaySymbol,
          unit: unit,
          currentPrice: current,
          currentTimestampUtc: now,
          levels: levels,
          dataNote: 'Source: Stooq daily CSV (proxy).',
          error: null,
        );
      } else {
        final priceData = await _fetchCoinGeckoSimplePrice(coinId!, vsCurrency!);
        final current = priceData.price;
        final now = priceData.timestampUtc;

        final ohlc = await _fetchCoinGeckoOhlcDaily(
          coinId!,
          vsCurrency!,
          days: 365,
        );

        final dailyCandles = ohlc
            .map((e) => Candle(
                  date: DateTime.fromMillisecondsSinceEpoch(e.timestampMs, isUtc: true),
                  open: e.open,
                  high: e.high,
                  low: e.low,
                  close: e.close,
                ))
            .toList()
          ..sort((a, b) => a.date.compareTo(b.date));

        final levels = computeLevelsFromDaily(
          candles: dailyCandles,
          currentPrice: current,
          currentTimestampUtc: now,
        );

        return AssetSnapshot(
          assetKey: key,
          title: title,
          symbol: displaySymbol,
          unit: unit,
          currentPrice: current,
          currentTimestampUtc: now,
          levels: levels,
          dataNote: 'Source: CoinGecko (/simple/price + /ohlc).',
          error: null,
        );
      }
    } catch (e) {
      return AssetSnapshot.error(
        assetKey: key,
        title: title,
        symbol: displaySymbol,
        unit: unit,
        error: e.toString(),
      );
    }
  }
}

class Candle {
  final DateTime date; // UTC date
  final double open;
  final double high;
  final double low;
  final double close;

  Candle({
    required this.date,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
  });
}

class OhlcPoint {
  final int timestampMs;
  final double open, high, low, close;
  OhlcPoint(this.timestampMs, this.open, this.high, this.low, this.close);
}

class SimplePrice {
  final double price;
  final DateTime timestampUtc;
  SimplePrice(this.price, this.timestampUtc);
}

ComputedLevels computeLevelsFromDaily({
  required List<Candle> candles,
  required double currentPrice,
  required DateTime currentTimestampUtc,
}) {
  if (candles.isEmpty) {
    throw Exception('No candles returned.');
  }

  final last = candles.last;

  final daily = RangeLevel(
    label: 'Daily (last)',
    start: DateTime.utc(last.date.year, last.date.month, last.date.day),
    end: DateTime.utc(last.date.year, last.date.month, last.date.day),
    high: last.high,
    low: last.low,
  );

  final lastIso = isoWeek(last.date);
  final prevIso = prevIsoWeek(lastIso);

  final weeklyCandles = candles.where((c) {
    final w = isoWeek(c.date);
    return w.year == prevIso.year && w.week == prevIso.week;
  }).toList();

  RangeLevel weekly;
  if (weeklyCandles.isEmpty) {
    final tail = candles.length >= 5 ? candles.sublist(candles.length - 5) : candles;
    weekly = RangeLevel(
      label: 'Weekly (fallback 5d)',
      start: tail.first.date,
      end: tail.last.date,
      high: tail.map((e) => e.high).reduce(math.max),
      low: tail.map((e) => e.low).reduce(math.min),
    );
  } else {
    weekly = RangeLevel(
      label: 'Weekly (prev ISO)',
      start: weeklyCandles.first.date,
      end: weeklyCandles.last.date,
      high: weeklyCandles.map((e) => e.high).reduce(math.max),
      low: weeklyCandles.map((e) => e.low).reduce(math.min),
    );
  }

  final y0 = DateTime.utc(last.date.year, 1, 1);
  final ytdCandles = candles.where((c) => !c.date.isBefore(y0)).toList();

  final ytd = RangeLevel(
    label: 'YTD',
    start: y0,
    end: last.date,
    high: ytdCandles.map((e) => e.high).reduce(math.max),
    low: ytdCandles.map((e) => e.low).reduce(math.min),
  );

  return ComputedLevels(
    daily: daily,
    weekly: weekly,
    ytd: ytd,
    currentPrice: currentPrice,
    currentTimestampUtc: currentTimestampUtc,
  );
}

class ComputedLevels {
  final RangeLevel daily;
  final RangeLevel weekly;
  final RangeLevel ytd;
  final double currentPrice;
  final DateTime currentTimestampUtc;

  ComputedLevels({
    required this.daily,
    required this.weekly,
    required this.ytd,
    required this.currentPrice,
    required this.currentTimestampUtc,
  });

  Zone verdictFor(
    RangeLevel r, {
    double buyThreshold = 0.25,
    double sellThreshold = 0.75,
  }) {
    final pos = r.position(currentPrice);
    if (pos == null) return Zone.neutral;
    if (pos <= buyThreshold) return Zone.buy;
    if (pos >= sellThreshold) return Zone.sell;
    return Zone.neutral;
  }

  Zone overallVerdict({
    double buyThreshold = 0.25,
    double sellThreshold = 0.75,
  }) {
    final v1 = verdictFor(daily, buyThreshold: buyThreshold, sellThreshold: sellThreshold);
    final v2 = verdictFor(weekly, buyThreshold: buyThreshold, sellThreshold: sellThreshold);
    final v3 = verdictFor(ytd, buyThreshold: buyThreshold, sellThreshold: sellThreshold);

    int buy = 0;
    int sell = 0;
    if (v1 == Zone.buy) buy++;
    if (v2 == Zone.buy) buy++;
    if (v3 == Zone.buy) buy++;
    if (v1 == Zone.sell) sell++;
    if (v2 == Zone.sell) sell++;
    if (v3 == Zone.sell) sell++;

    if (buy >= 2) return Zone.buy;
    if (sell >= 2) return Zone.sell;
    return Zone.neutral;
  }
}

class RangeLevel {
  final String label;
  final DateTime start;
  final DateTime end;
  final double high;
  final double low;

  RangeLevel({
    required this.label,
    required this.start,
    required this.end,
    required this.high,
    required this.low,
  });

  double? position(double current) {
    final denom = (high - low);
    if (denom.abs() < 1e-12) return null;
    return (current - low) / denom;
  }
}

enum Zone { buy, neutral, sell }

class AssetSnapshot {
  final String assetKey;
  final String title;
  final String symbol;
  final String unit;

  final double? currentPrice;
  final DateTime? currentTimestampUtc;
  final ComputedLevels? levels;

  final String? dataNote;
  final String? error;

  AssetSnapshot({
    required this.assetKey,
    required this.title,
    required this.symbol,
    required this.unit,
    required this.currentPrice,
    required this.currentTimestampUtc,
    required this.levels,
    required this.dataNote,
    required this.error,
  });

  factory AssetSnapshot.error({
    required String assetKey,
    required String title,
    required String symbol,
    required String unit,
    required String error,
  }) =>
      AssetSnapshot(
        assetKey: assetKey,
        title: title,
        symbol: symbol,
        unit: unit,
        currentPrice: null,
        currentTimestampUtc: null,
        levels: null,
        dataNote: null,
        error: error,
      );
}

class AssetCard extends StatelessWidget {
  final AssetSnapshot snapshot;
  final VoidCallback onDelete;

  const AssetCard({
    super.key,
    required this.snapshot,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);
    final priceStyle = theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('${snapshot.symbol} - ${snapshot.title}', style: titleStyle),
                ),
                IconButton(
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Delete',
                ),
                if (snapshot.error == null)
                  _ZoneChip(
                    zone: snapshot.levels!.overallVerdict(),
                    labelPrefix: 'Global',
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (snapshot.error != null)
              Text(
                'Source error: ${snapshot.error}',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
              )
            else
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${snapshot.unit}${_fmt(snapshot.currentPrice!)}', style: priceStyle),
                  const SizedBox(width: 10),
                  Opacity(
                    opacity: 0.7,
                    child: Text(
                      'upd ${_fmtTs(snapshot.currentTimestampUtc!)}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 12),
            if (snapshot.error == null) ...[
              _RangeBlock(levels: snapshot.levels!),
              const SizedBox(height: 10),
              Opacity(
                opacity: 0.75,
                child: Text(snapshot.dataNote ?? '', style: theme.textTheme.bodySmall),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RangeBlock extends StatelessWidget {
  final ComputedLevels levels;
  const _RangeBlock({required this.levels});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _RangeRow(
          level: levels.daily,
          current: levels.currentPrice,
          zone: levels.verdictFor(levels.daily),
        ),
        const SizedBox(height: 10),
        _RangeRow(
          level: levels.weekly,
          current: levels.currentPrice,
          zone: levels.verdictFor(levels.weekly),
        ),
        const SizedBox(height: 10),
        _RangeRow(
          level: levels.ytd,
          current: levels.currentPrice,
          zone: levels.verdictFor(levels.ytd),
        ),
      ],
    );
  }
}

class _RangeRow extends StatelessWidget {
  final RangeLevel level;
  final double current;
  final Zone zone;

  const _RangeRow({
    required this.level,
    required this.current,
    required this.zone,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final small = theme.textTheme.bodySmall;
    final medium = theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700);

    final pos = level.position(current);
    final posClamped = pos == null ? 0.5 : pos.clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${level.label} - ${_fmtDate(level.start)}'
                '${(level.end.difference(level.start).inDays == 0) ? '' : ' -> ${_fmtDate(level.end)}'}',
                style: small?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
            _ZoneChip(zone: zone, labelPrefix: null),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: posClamped.toDouble(),
            minHeight: 10,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            Expanded(child: Text('Low  ${_fmt(level.low)}', style: medium)),
            Expanded(
              child: Text(
                'High ${_fmt(level.high)}',
                style: medium,
                textAlign: TextAlign.right,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _ZoneChip extends StatelessWidget {
  final Zone zone;
  final String? labelPrefix;

  const _ZoneChip({required this.zone, required this.labelPrefix});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    String label;
    Color color;
    if (zone == Zone.buy) {
      label = 'Buy';
      color = Colors.green;
    } else if (zone == Zone.sell) {
      label = 'Sell';
      color = Colors.red;
    } else {
      label = 'Neutral';
      color = Colors.grey;
    }

    final txt = labelPrefix == null ? label : '$labelPrefix: $label';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Text(
        txt,
        style: theme.textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class AddAssetSheet extends StatefulWidget {
  const AddAssetSheet({super.key});

  @override
  State<AddAssetSheet> createState() => _AddAssetSheetState();
}

class _AddAssetSheetState extends State<AddAssetSheet> {
  AssetSource _source = AssetSource.stooq;

  final _titleCtrl = TextEditingController();
  final _symbolCtrl = TextEditingController();
  final _displayCtrl = TextEditingController();
  final _unitCtrl = TextEditingController(text: r'$');
  final _vsCtrl = TextEditingController(text: 'usd');

  String? _error;

  @override
  void dispose() {
    _titleCtrl.dispose();
    _symbolCtrl.dispose();
    _displayCtrl.dispose();
    _unitCtrl.dispose();
    _vsCtrl.dispose();
    super.dispose();
  }

  void _submit() {
    setState(() => _error = null);

    final title = _titleCtrl.text.trim();
    final key = _symbolCtrl.text.trim();
    final disp = _displayCtrl.text.trim();
    final unit = _unitCtrl.text.trim();

    if (title.isEmpty || key.isEmpty || disp.isEmpty) {
      setState(() => _error = 'Name, identifier and display symbol are required.');
      return;
    }

    if (_source == AssetSource.stooq) {
      Navigator.pop(
        context,
        Asset.stooq(
          title: title,
          symbol: key.toLowerCase(),
          displaySymbol: disp,
          unit: unit,
        ),
      );
      return;
    }

    final vs = _vsCtrl.text.trim().toLowerCase();
    if (vs.isEmpty) {
      setState(() => _error = 'vs_currency required (example: usd).');
      return;
    }

    Navigator.pop(
      context,
      Asset.coingecko(
        title: title,
        coinId: key.toLowerCase(),
        displaySymbol: disp,
        vsCurrency: vs,
        unit: unit,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add asset',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          SegmentedButton<AssetSource>(
            segments: const [
              ButtonSegment(value: AssetSource.stooq, label: Text('Stooq')),
              ButtonSegment(value: AssetSource.coingecko, label: Text('CoinGecko')),
            ],
            selected: <AssetSource>{_source},
            onSelectionChanged: (s) => setState(() => _source = s.first),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(labelText: 'Name (example: Nasdaq 100)'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _symbolCtrl,
            decoration: InputDecoration(
              labelText: _source == AssetSource.stooq
                  ? 'Stooq symbol (example: nq.f, xauusd)'
                  : 'CoinGecko coin id (example: bitcoin)',
            ),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _displayCtrl,
            decoration: const InputDecoration(labelText: 'Display symbol (example: NQ.F, BTC)'),
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _unitCtrl,
                  decoration: const InputDecoration(labelText: 'Unit (example: \$, EUR)'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 150),
                  child: _source == AssetSource.coingecko
                      ? TextField(
                          key: const ValueKey('vs'),
                          controller: _vsCtrl,
                          decoration: const InputDecoration(labelText: 'vs_currency (example: usd)'),
                        )
                      : const SizedBox.shrink(key: ValueKey('vs-empty')),
                ),
              ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: _submit,
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// -------------------- Data fetchers --------------------

Future<List<Candle>> _fetchStooqDailyCandlesWithRetry(String symbol) async {
  // Try a few variants to fix empty-body cases on some networks / hosting.
  final variants = <String>[
    symbol,
    symbol.toLowerCase(),
    symbol.toUpperCase(),
  ];

  Exception? lastError;
  for (final s in variants) {
    try {
      final candles = await _fetchStooqDailyCandles(s);
      if (candles.isNotEmpty) return candles;
    } catch (e) {
      lastError = Exception(e.toString());
    }
  }

  throw lastError ?? Exception('Stooq failed for symbol: $symbol');
}

Future<List<Candle>> _fetchStooqDailyCandles(String symbol) async {
  final url = Uri.https('stooq.com', '/q/d/l/', <String, String>{
    's': symbol,
    'i': 'd',
  });

  final resp = await http.get(url, headers: <String, String>{
    'User-Agent': 'Mozilla/5.0 (InvestApp)',
    'Accept': 'text/csv,text/plain;q=0.9,*/*;q=0.8',
  });

  if (resp.statusCode != 200) {
    throw Exception('Stooq HTTP ${resp.statusCode}');
  }

  if (resp.body.trim().isEmpty) {
    throw Exception('Stooq returned empty body for $url');
  }

  final rawLines = const LineSplitter().convert(resp.body);

  final lines = rawLines
      .map((l) => l.replaceAll('\ufeff', '').trim())
      .where((l) => l.isNotEmpty)
      .toList();

  if (lines.length < 2) {
    final preview = lines.isEmpty ? 'EMPTY' : lines.take(3).join(' | ');
    throw Exception('Stooq CSV too short for $url. First lines: $preview');
  }

  final header = lines.first.toLowerCase();
  if (!header.contains('date') || !header.contains('close')) {
    throw Exception('Stooq CSV invalid header for $url. Preview: ${lines.take(5).join(" | ")}');
  }

  final candles = <Candle>[];
  for (int i = 1; i < lines.length; i++) {
    final parts = lines[i].split(',');
    if (parts.length < 5) continue;

    final date = DateTime.tryParse(parts[0]);
    if (date == null) continue;

    final open = double.tryParse(parts[1]) ?? double.nan;
    final high = double.tryParse(parts[2]) ?? double.nan;
    final low = double.tryParse(parts[3]) ?? double.nan;
    final close = double.tryParse(parts[4]) ?? double.nan;

    if (open.isNaN || high.isNaN || low.isNaN || close.isNaN) continue;

    candles.add(Candle(
      date: DateTime.utc(date.year, date.month, date.day),
      open: open,
      high: high,
      low: low,
      close: close,
    ));
  }

  candles.sort((a, b) => a.date.compareTo(b.date));
  if (candles.isEmpty) throw Exception('Stooq returned empty candles for $url.');
  return candles;
}

Future<SimplePrice> _fetchCoinGeckoSimplePrice(String id, String vs) async {
  final url = Uri.https('api.coingecko.com', '/api/v3/simple/price', <String, String>{
    'ids': id,
    'vs_currencies': vs,
    'include_last_updated_at': 'true',
  });

  final resp = await http.get(url, headers: <String, String>{
    'User-Agent': 'Mozilla/5.0 (InvestApp)',
    'Accept': 'application/json',
  });

  if (resp.statusCode == 429) {
    throw Exception('CoinGecko rate limited (HTTP 429). Wait a bit and refresh.');
  }
  if (resp.statusCode != 200) {
    throw Exception('CoinGecko HTTP ${resp.statusCode}');
  }

  final jsonMap = json.decode(resp.body) as Map<String, dynamic>;
  final coin = jsonMap[id] as Map<String, dynamic>?;
  if (coin == null) throw Exception('CoinGecko: missing coin id.');

  final price = (coin[vs] as num).toDouble();
  final ts = (coin['last_updated_at'] as num?)?.toInt();

  final dt = ts == null
      ? DateTime.now().toUtc()
      : DateTime.fromMillisecondsSinceEpoch(ts * 1000, isUtc: true);

  return SimplePrice(price, dt);
}

Future<List<OhlcPoint>> _fetchCoinGeckoOhlcDaily(
  String id,
  String vs, {
  int days = 370,
}) async {
  final url = Uri.https('api.coingecko.com', '/api/v3/coins/$id/ohlc', <String, String>{
    'vs_currency': vs,
    'days': days.toString(),
  });

  final resp = await http.get(url, headers: <String, String>{
    'User-Agent': 'Mozilla/5.0 (InvestApp)',
    'Accept': 'application/json',
  });

  if (resp.statusCode == 429) {
    throw Exception('CoinGecko rate limited (HTTP 429). Wait a bit and refresh.');
  }
  if (resp.statusCode != 200) {
    throw Exception('CoinGecko OHLC HTTP ${resp.statusCode}');
  }

  final arr = json.decode(resp.body);
  if (arr is! List) throw Exception('CoinGecko OHLC unexpected format.');

  return arr.map<OhlcPoint>((e) {
    final l = (e as List).cast<num>();
    return OhlcPoint(
      l[0].toInt(),
      l[1].toDouble(),
      l[2].toDouble(),
      l[3].toDouble(),
      l[4].toDouble(),
    );
  }).toList();
}

// -------------------- Formatting helpers --------------------

String _fmt(double v) => NumberFormat('#,##0.##', 'en_US').format(v);

String _fmtTs(DateTime utc) {
  final local = utc.toLocal();
  return DateFormat('dd/MM HH:mm').format(local);
}

String _fmtDate(DateTime utc) {
  final local = utc.toLocal();
  return DateFormat('yyyy-MM-dd').format(local);
}

// -------------------- ISO week helpers --------------------

class IsoWeek {
  final int year;
  final int week;
  const IsoWeek(this.year, this.week);
}

IsoWeek isoWeek(DateTime dateUtc) {
  final d = DateTime.utc(dateUtc.year, dateUtc.month, dateUtc.day);
  final dayOfWeek = d.weekday; // Mon=1..Sun=7
  final thursday = d.add(Duration(days: 4 - dayOfWeek));
  final weekYear = thursday.year;

  final firstThursday = DateTime.utc(weekYear, 1, 4);
  final firstThursdayDay = firstThursday.weekday;
  final firstWeekThursday = firstThursday.add(Duration(days: 4 - firstThursdayDay));

  final diffDays = thursday.difference(firstWeekThursday).inDays;
  final week = 1 + (diffDays ~/ 7);

  return IsoWeek(weekYear, week);
}

IsoWeek prevIsoWeek(IsoWeek w) {
  if (w.week > 1) return IsoWeek(w.year, w.week - 1);
  final dec28 = DateTime.utc(w.year - 1, 12, 28);
  return isoWeek(dec28);
}

