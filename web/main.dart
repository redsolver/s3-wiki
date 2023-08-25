import 'dart:convert';
import 'dart:html';
import 'dart:js';

import 'package:s3_wiki/js.dart';

late List<Map> data;

final ranges = [
  [0, 10],
  [10, 100],
  [100, 500],
  [500, 2000],
  [2000, 5000],
  [5000, 20000],
  [20000, 100000],
  [100000, 1000000],
  [1000000, 0],
];

String protocol = 's3';

void onClick(String key, String value) {
  print('onClick $key $value');
  protocol = value;
  setState();
}

void main() async {
  final res = await window.fetch('/static/providers.json');

  clickJS = allowInterop(onClick);

  final str = await res.text();
  data = json.decode(str).cast<Map>();

  updateChipsHtml();

  // print(data);

  querySelector('#storage')!.onInput.listen((event) {
    final value = (querySelector('#storage')! as InputElement).valueAsNumber;

    mbStorage = mapValueToRange(value!);
    setState();
  });

  querySelector('#traffic')!.onInput.listen((event) {
    final value = (querySelector('#traffic')! as InputElement).valueAsNumber;

    mbTrafficEgress = mapValueToRange(value!);
    setState();
  });
  setState();
}

int mapValueToRange(num value) {
  final index = (value / 10000).floor();

  final range = ranges[index];

  return (range[0] + (range[1] - range[0]) * ((value % 10000) / 10000)).round();
}

int mbStorage = 1000;
int mbTrafficEgress = 300;

void setState() {
  processInput(mbStorage, mbTrafficEgress);
}

void processInput(int mbStorage, int mbTrafficEgress) {
  final results = calculate(
    (mbStorage * 1000000000).round(),
    (mbTrafficEgress * 1000000000).round(),
    [protocol],
  );

  querySelector('#input1')?.text = mbStorage > 1000
      ? 'Storage: ${mbStorage / 1000} TB'
      : 'Storage: $mbStorage GB';

  querySelector('#input2')?.text = mbTrafficEgress > 1000
      ? 'Egress Traffic: ${mbTrafficEgress / 1000} TB'
      : 'Egress Traffic: $mbTrafficEgress GB';

  var html = '';
  for (final r in results) {
    html += '''
<div class="result">
  <a href="${r['url']}" target="_blank">${r['provider']} ${r['plan']}</a>
  <span style="font-weight: bold">${(r['cost'] as double).toStringAsFixed(2)} USD/month</span>
  <span>Protocols: ${r['protocols'].join(', ')}</span>
</div>
''';
  }

  // querySelector('#output')?.text = JsonEncoder.withIndent(' ').convert(results);
  ;
  querySelector('#output')
      ?.setInnerHtml(html, validator: TrustedNodeValidator());
}

void updateChipsHtml() {
  var html = '''    <span>Protocol</span>

      <div class="protocol_option selected"
        onclick="document.querySelectorAll('.protocol_option').forEach((e)=>e.classList.remove('selected')); this.classList.add('selected');clickjs('protocol', 's3')">
        s3</div>

''';

  for (final p in [
    // 's3',
    'skynet',
    'webdav',
    // more
    'borg',
    'sftp',
    'samba',
    'rsync',
    'ftps',
    'ftp',
    'scp',
  ]) {
    html += '''
      <div class="protocol_option"
        onclick="document.querySelectorAll('.protocol_option').forEach((e)=>e.classList.remove('selected')); this.classList.add('selected');clickjs('protocol', '$p')">
        $p</div>''';
  }

  document.getElementById('protocolOptions')!.setInnerHtml(
        html,
        validator: TrustedNodeValidator(),
      );
}

class TrustedNodeValidator implements NodeValidator {
  @override
  bool allowsElement(Element element) => true;
  @override
  bool allowsAttribute(element, attributeName, value) => true;
}

final allProtocols = <String>{};

List<Map> calculate(
  int storage,
  int mbTrafficEgress,
  List<String> allowedProtocols,
) {
  print('allProtocols ${allProtocols.toList()}');
  final results = <Map>[];

  for (final provider in data) {
    bool supportsProtocol = false;
    allProtocols.addAll(provider['protocols'].cast<String>());
    for (final a in allowedProtocols) {
      if (provider['protocols'].contains(a)) {
        supportsProtocol = true;
        break;
      }
    }
    if (!supportsProtocol) continue;

    for (final plan in provider['plans']) {
      final int included = plan['storage']['included'] ?? 0;

      final remaining = storage - included;

      int includedEgressTraffic = plan['trafficEgress']?['included'] ??
          plan['trafficAll']?['included'] ??
          0;

      final int includedStorageMultiplier = plan['trafficEgress']
              ?['includedStorageMultiplier'] ??
          plan['trafficAll']?['includedStorageMultiplier'] ??
          0;

      includedEgressTraffic += includedStorageMultiplier * storage;

      final remainingTraffic = includedEgressTraffic == -1
          ? 0
          : mbTrafficEgress - includedEgressTraffic;

      var cost = calculateCost(
        plan['baseCost'] is List ? plan['baseCost'][0] : plan['baseCost'],
      );
      if (cost < 0) continue;

      void addResult() {
        results.add({
          'provider': provider['name'],
          'plan': plan['name'],
          'url': provider['url'],
          'cost': cost,
          'protocols': provider['protocols'],
        });
      }

      if (remaining <= 0 && remainingTraffic <= 0) {
        addResult();
      } else {
        if (remaining > 0) {
          final more = plan['storage']['more'];
          if (more == null) {
            continue;
          } //
          final count = remaining / more['per'];
          cost += count * calculateCost(more['cost']);
        }

        if (remainingTraffic > 0) {
          final more = plan['trafficEgress']?['more'];
          if (more == null) {
            continue;
          }
          final count = remainingTraffic / more['per'];
          cost += count * calculateCost(more['cost']);
        }
        addResult();
      }
    }
  }

  results.sort((a, b) => a['cost'].compareTo(b['cost']));

  return results;
}

double calculateCost(Map cost) {
  double value = cost['value'] + 0.0;
  if (cost['vat'] == false) {
    value *= 1.19;
  }
  final interval = cost['interval'] ?? 2629800;

  final ratio = 2629800 / interval;

  return value * ratio;
}
